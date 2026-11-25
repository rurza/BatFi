//
//  SailingLimitHold.swift
//  BatFi
//
//  Sailing's hold where macOS enforces the charge limit and BatFi only sets its value
//  (`.systemChargeLimit`). There is no "stop charging" to hold with: macOS stops at the limit
//  in force and, once stopped, does not resume by itself — but any *change* to that value makes
//  it charge again. So the hold is a value that is kept, not one that is written:
//
//  - A hold that began at the limit keeps the limit. Nothing new is written; macOS has already
//    stopped there, and BatFi simply does not force the resume until the phase says charge.
//  - A hold that began inside the range (a charger connected at 76% under an 80% limit) freezes
//    the limit at the current charge, as a manual pause does — rounded down to a step of five
//    from 80 up, because that is the path that takes it. powerd takes most of a minute to adopt
//    it, so a little charge goes in first.
//  - For as long as the hold lasts the kept value is requested whatever the levels say. A slider
//    move or a rule changes the levels inside BatFi at once and reaches macOS when the next
//    charging phase begins; writing it sooner would start a charge. The one exception is a limit
//    lowered to the battery or under it, which cannot start a charge: the hold moves down to it
//    and macOS drains there, as it does with sailing off.
//  - A hot battery's frozen value under the kept one is taken over, so the hot hold's release
//    writes nothing.
//
//  In memory only, like the hot-battery hold: quit, a crash, licence loss and charge
//  management switched off all hand charging back to macOS, and the next engagement starts
//  afresh.
//

import Foundation
import Shared

public struct SailingLimitHold: Equatable, Sendable {
    /// The value BatFi keeps in force for the length of a hold; nil when not holding.
    public private(set) var heldLimit: Int?

    public init() {}

    /// The limit to request this pass.
    ///
    /// Holding under `.systemChargeLimit`: on entry the limit itself where the battery is at or
    /// above where macOS enforces it (the hold began at the limit — nothing new to write, or a battery above it drains
    /// to it as it does with sailing off); otherwise `limitInForce` where it already sits at the
    /// battery's frozen level (a manual pause handing over), else a freeze at
    /// `HotBatteryHold.frozenLimit(batteryLevel:)`. For the rest of the hold `heldLimit`,
    /// whatever `otherwise` says — except that a limit lowered to the battery's level or under
    /// it (judged at the learned `floor`) moves the hold down to it: a value there cannot start
    /// a charge, and macOS drains to it as it does with sailing off. From 80 up the moved value
    /// is rounded down to a step of five, as a freeze is. Any other phase or backend: clear and
    /// return `otherwise`.
    ///
    /// A hot battery's frozen value (`hotBatteryHoldLimit`) under the hold's is taken over, as
    /// a manual pause's is on entry: the hot hold's release would otherwise write the hold's
    /// higher value back, and that change starts a charge under a label that says "on hold".
    ///
    /// A value in force well under the battery — a discharge's target — is never kept: macOS
    /// would drain the battery to it on mains power.
    public mutating func requestedLimit(
        phase: SailingPhase?,
        backend: ChargeBackend?,
        batteryLevel: Int,
        limitInForce: Int?,
        otherwise limit: Int,
        floor: Int? = nil,
        hotBatteryHoldLimit: Int? = nil
    ) -> Int {
        guard phase == .holding, HotBatteryHold.applies(to: backend) else {
            heldLimit = nil
            return limit
        }
        var held: Int
        if let heldLimit {
            held = heldLimit
            if limit < held, ChargingAheadOfApply.willApply(requested: limit, floor: floor) <= batteryLevel {
                held = HotBatteryHold.frozenLimit(batteryLevel: limit)
            }
        } else {
            held = Self.entryLimit(batteryLevel: batteryLevel, limitInForce: limitInForce, otherwise: limit, floor: floor)
        }
        if let hotBatteryHoldLimit {
            held = min(held, hotBatteryHoldLimit)
        }
        heldLimit = held
        return held
    }

    /// The limit macOS will enforce for `requested`: the learned floor below 80
    /// (`ChargingAheadOfApply.willApply`), and from 80 up the next step of five, which is where
    /// macOS puts an off-step request — 87 is enforced as 90. What the sailing levels are
    /// judged against, so a rule's or a shortcut's 87 holds at the 90 macOS charges to.
    public static func limitMacOSEnforces(requested: Int, floor: Int?) -> Int {
        let applied = ChargingAheadOfApply.willApply(requested: requested, floor: floor)
        guard applied >= 80, applied % 5 != 0 else { return applied }
        return min(100, applied + 5 - applied % 5)
    }

    /// Whether a freeze at this level would hold on this Mac (false where a sub-80 value is
    /// raised by the learned floor above the battery).
    public static func freezeCanHold(batteryLevel: Int, floor: Int?) -> Bool {
        let frozen = HotBatteryHold.frozenLimit(batteryLevel: batteryLevel)
        return ChargingAheadOfApply.willApply(requested: frozen, floor: floor) <= batteryLevel
    }

    /// Whether the hold this pass enters cannot be expressed, so the pass charges to the limit
    /// and sails from there: where macOS refuses a limit below 80, a connection inside the range
    /// (the owner's fallback for those Macs); and anywhere, a battery at or above the request
    /// but under where macOS enforces it — an off-step 87 enforced as 90 over a battery at 88 —
    /// where the request itself is a charge to 90.
    ///
    /// The limit is judged where macOS enforces it (`limitMacOSEnforces`), so a 70% request on
    /// such a Mac is the 80% it is enforced at. Only on entry: a hold already in force goes on with what it
    /// keeps.
    public func cannotHoldOnEntry(
        phase: SailingPhase?,
        backend: ChargeBackend?,
        batteryLevel: Int,
        limitInForce: Int?,
        otherwise limit: Int,
        floor: Int?
    ) -> Bool {
        guard phase == .holding, HotBatteryHold.applies(to: backend), heldLimit == nil else { return false }
        let enforced = Self.limitMacOSEnforces(requested: limit, floor: floor)
        guard batteryLevel < enforced else { return false }
        // Between the request and where macOS enforces it (87 asked, enforced as 90, battery at
        // 88): requesting the limit is a charge to 90, so a hold "at the limit" would say "on
        // hold" over a battery taking charge. Charge to the limit first and hold from there.
        if limit <= batteryLevel { return true }
        if let limitInForce, Self.canKeep(limitInForce, batteryLevel: batteryLevel) { return false }
        return !Self.freezeCanHold(batteryLevel: batteryLevel, floor: floor)
    }

    /// Whether the value kept is one the person did not set: a freeze, or the limit they had
    /// when the hold began after the levels have since moved. Read as BatFi's own short-lived
    /// value, the way a hot battery's or a manual pause's frozen limit is. A hold at the
    /// person's own limit is not one — macOS's top-up and drain there are told as they are
    /// with sailing off.
    public func keepsAValueOtherThan(_ limit: Int) -> Bool {
        heldLimit.map { $0 != limit } ?? false
    }

    /// Whether an apply put the hold's value above the battery, so the hold cannot stand: the
    /// first sub-80 request of a process on a Mac whose floor was not learned yet. Nil
    /// (a failed apply) says nothing.
    ///
    /// macOS's own step from 80 up is not a raise: an off-step 87 is applied as 90, the 90 the
    /// levels were judged at, every pass of a hold that began there. Only a value past that
    /// rounding counts — the floor, which this check exists to catch, so it is left out.
    public static func applyRaisedItAboveTheBattery(requested: Int, applied: Int?, batteryLevel: Int) -> Bool {
        guard let applied else { return false }
        return applied > limitMacOSEnforces(requested: requested, floor: nil) && applied > batteryLevel
    }

    /// The battery is judged against the limit macOS enforces, not the raw request: an off-step
    /// 87 is enforced as 90, so over a battery at 88 it is a charge, not a hold at the limit.
    private static func entryLimit(batteryLevel: Int, limitInForce: Int?, otherwise limit: Int, floor: Int?) -> Int {
        if limitMacOSEnforces(requested: limit, floor: floor) <= batteryLevel { return limit }
        if let limitInForce, canKeep(limitInForce, batteryLevel: batteryLevel) { return limitInForce }
        return HotBatteryHold.frozenLimit(batteryLevel: batteryLevel)
    }

    /// A value already in force that holds the battery where it is: at or under it, and no
    /// further under it than a freeze would put it.
    private static func canKeep(_ limitInForce: Int, batteryLevel: Int) -> Bool {
        limitInForce <= batteryLevel && limitInForce >= HotBatteryHold.frozenLimit(batteryLevel: batteryLevel)
    }
}
