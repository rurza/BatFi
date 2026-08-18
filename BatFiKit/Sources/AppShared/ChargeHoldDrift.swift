//
//  ChargeHoldDrift.swift
//
//
//  Whether the battery is doing something BatFi's own configuration says it cannot.
//
//  Every mechanism BatFi drives is written and then believed: the helper records what it
//  applied and skips the write on later passes, and nothing asks the battery whether the
//  limit is still holding. That is the shape of the failure users report as "the limit
//  stopped working" — macOS retires the policy underneath, or another app takes the
//  mechanism over, and BatFi goes on reporting the limit it once applied.
//
//  So this asks the outcome rather than the plumbing: a reading that contradicts the hold
//  is a fault whatever caused it, including causes nobody has characterised yet. The two
//  questions below are deliberately different in strength, and both are needed — see
//  `isDrifting`.
//

import Foundation

public enum ChargeHoldDrift {
    /// Whether this reading contradicts the hold BatFi's configuration implies.
    ///
    /// - Parameters:
    ///   - chargerConnected: nothing is being held back off the charger.
    ///   - isCharging: `kIOPSIsChargingKey` — current actually flowing **into** the battery,
    ///     not merely that a charger is attached. Measured false on 26A5416b while macOS
    ///     drained a 74% battery toward a 60% limit on mains, which is the state this must
    ///     never call a fault.
    ///   - batteryLevel: current percentage.
    ///   - limitInForce: the limit actually applied, not the one requested. The two come
    ///     apart under `.systemChargeLimit`, and charging is governed by the former.
    ///   - holdIsAttributed: whether the firmware names something holding charge back right
    ///     now — `CHNC` bit 24 for Apple's limit, bits 14/15 for BatFi's own inhibit. **Nil
    ///     where it was not asked, or where the backend has no attribution bit at all**
    ///     (`.firmwareRange` has none, which is the same reason the MagSafe green light is
    ///     disabled there). Nil is "no evidence", never "nothing is holding".
    ///
    /// Two contradictions, because one signal cannot see both halves of the failure:
    ///
    /// **Charging at or above the limit.** The plain one, free to evaluate, true on every
    /// backend. It catches the fault while it is happening, which is the common case: the
    /// limit goes, the battery climbs, and the user watches it pass the number they set.
    ///
    /// **Sitting above the limit with nothing holding it.** Once the battery reaches 100%
    /// nothing is charging any more, so the first question goes quiet and the Mac stays
    /// broken — which is exactly the state a user is in when they finally write in. The
    /// level alone cannot stand in for it: sitting above the limit on the charger is
    /// ordinary under every inhibit backend, and under Apple's limit it is a drain in
    /// progress. Only the firmware's own attribution separates "held above the limit" from
    /// "nothing is holding this at all", which is why the strong question is asked of the
    /// firmware and the weak one is not.
    public static func isDrifting(
        chargerConnected: Bool,
        isCharging: Bool,
        batteryLevel: Int,
        limitInForce: Int,
        holdIsAttributed: Bool?
    ) -> Bool {
        guard chargerConnected else { return false }
        if isCharging, batteryLevel >= limitInForce { return true }
        if !isCharging, batteryLevel > limitInForce, holdIsAttributed == false { return true }
        return false
    }
}

/// The escalation clock over a run of readings.
///
/// A single drifting reading is not worth acting on: charging can tick on for a moment at
/// exactly the limit as the mechanism catches it, and a re-apply per status pass would be a
/// write to a control the user can see. A run that survives a minute is a fault, and one
/// that survives ten minutes of re-applying is a fault BatFi cannot fix by itself and the
/// user is entitled to hear about.
///
/// Time, not passes. `updateStatus` runs on power-source changes, so a battery climbing past
/// its limit produces passes faster than a settled one — counting passes would make the
/// thresholds depend on how fast the fault progresses.
public struct ChargeHoldDriftMonitor: Equatable, Sendable {
    /// How long a run must last before BatFi re-applies the limit.
    public static let reapplyAfter: TimeInterval = 60
    /// How long a run must last, with re-applies not fixing it, before the user is told.
    public static let warnAfter: TimeInterval = 600
    /// How often the firmware's attribution is worth an XPC round trip.
    ///
    /// `chargingDiagnostics()` opens the SMC, reads `CHNC`, queries PowerUI and probes three
    /// more keys, on an actor that also serves `applyChargeLimit` — asking it per pass is a
    /// mistake this codebase has already made once, for the MagSafe green light. The steady
    /// state it detects has no deadline, so a five-minute answer is as good as an instant one.
    public static let attributionInterval: TimeInterval = 300

    public enum Response: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// Put the limit back in force, bypassing whatever the helper believes it applied.
        case reapply
        /// Re-apply, and tell the user this time. Raised once per run.
        case warnTheUser
    }

    public private(set) var driftingSince: Date?
    public private(set) var hasWarned: Bool = false
    /// When the caller was last told to do something about this run.
    ///
    /// The floor between re-applies, and the reason it is needed: passes arrive on
    /// power-source changes rather than on a timer, so a battery climbing past its limit
    /// produces them seconds apart. Acting on each would re-write the mechanism at that
    /// rate for as long as a fault lasted — and under `.firmwareRange` every re-apply
    /// re-runs `engageSequence`, whose first write disarms the band.
    private var lastActedAt: Date?

    public init() {}

    /// Folds one reading in and says what to do about it.
    ///
    /// `.warnTheUser` implies the re-apply as well — the caller does both — so the run keeps
    /// being corrected after the warning rather than being handed over to the user.
    public mutating func record(isDrifting: Bool, at now: Date) -> Response {
        guard isDrifting else {
            // One clean reading ends the run. The fault is a steady state, so a run that
            // breaks was either fixed or was never one.
            driftingSince = nil
            hasWarned = false
            lastActedAt = nil
            return .none
        }
        guard let start = driftingSince else {
            driftingSince = now
            return .none
        }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= Self.reapplyAfter else { return .none }
        // Checked ahead of the floor, and deliberately: the warning is a once-per-run event
        // of its own, and a run that has been failing for ten minutes has to be able to say
        // so on the pass that crosses the line, whatever happened seconds earlier.
        if elapsed >= Self.warnAfter, !hasWarned {
            hasWarned = true
            lastActedAt = now
            return .warnTheUser
        }
        if let lastActedAt, now.timeIntervalSince(lastActedAt) < Self.reapplyAfter { return .none }
        lastActedAt = now
        return .reapply
    }
}
