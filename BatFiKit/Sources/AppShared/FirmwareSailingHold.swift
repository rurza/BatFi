//
//  FirmwareSailingHold.swift
//  BatFi
//
//  Sailing's hold where the firmware holds a band (`.firmwareRange`), enforced by BatFi.
//
//  Handed the band `resume…limit` and left to itself, the firmware finishes a charge that is
//  already running inside the range — after BatFi was relaunched (a quitting BatFi releases the
//  band, and macOS starts charging), or any other way — although sailing should be holding.
//  What stops it is the upper bound: on this firmware an upper bound at the battery's level
//  stops charging, even a charge in progress, and one below the battery drains it down to it.
//  So the hold is a band, as `SailingLimitHold` is a kept limit on `.systemChargeLimit`:
//
//  - A hold that began at the limit (or above it) keeps the real band `resume…limit`. Nothing
//    new is written; the firmware has stopped there by itself.
//  - A hold that began inside the range hands the firmware `resume…battery`: the upper bound at
//    the level the hold began at, the lower bound at the resume level, so the firmware stops
//    and does not start again until the battery is below the resume level — asleep as well.
//  - The held value is kept for the length of the hold and not rewritten every pass. It never
//    goes under the battery, which would drain it: sailing only withholds charging. A battery
//    that rose before the write bit moves it up to the battery; one that reaches the limit
//    hands back the real band.
//  - A fresh start of the phase (a wake, the end of Run on Battery or of another override),
//    a changed resume level, and a limit lowered under the held value all re-establish the
//    hold at the battery's level: a band is written then anyway, and an upper bound the battery
//    has fallen away from could start a charge up to it.
//  - A battery exactly at the resume level leaves no room for a lower bound under the upper
//    one; the lower bound goes one point under it. BatFi hands over the real band as soon as
//    the battery is below the resume level, so the only effect is during sleep, where the
//    firmware resumes one point later than "below the resume level".
//
//  Only with the two-value call: a helper that takes only the one-value call cannot be handed a
//  lower bound, and there the firmware keeps deciding, as before. A held band the client sent
//  as the one-value call instead (a refusal) ends this for the rest of the process.
//
//  In memory only: quit releases the band, and the next launch starts afresh.
//

import Foundation
import Shared

public struct FirmwareSailingHold: Equatable, Sendable {
    /// The band to hand the firmware: an upper bound and the resume level written under it.
    public struct Band: Equatable, Sendable {
        public let limit: Int
        public let resumeLevel: Int

        public init(limit: Int, resumeLevel: Int) {
            self.limit = limit
            self.resumeLevel = resumeLevel
        }
    }

    /// The upper bound kept for the length of a hold — the limit itself for a hold that began
    /// at it — or nil when not holding.
    public private(set) var heldLevel: Int?
    /// The resume level the held value was set against.
    private var heldResumeLevel: Int?
    /// False once a held band went out as the one-value call: BatFi stops enforcing the hold
    /// for the rest of the process and the firmware decides, as before.
    public private(set) var canHoldByBand = true

    public init() {}

    /// The held band to request this pass, or nil for the request the pass makes without one —
    /// the real band `resume…limit`.
    ///
    /// Only under `.firmwareRange`, in the holding phase, with sailing's `levels` in play.
    /// Anything else clears the hold. `startedAfresh` is the tracker's: the phase started anew
    /// this pass.
    public mutating func heldBand(
        phase: SailingPhase?,
        backend: ChargeBackend?,
        startedAfresh: Bool,
        batteryLevel: Int,
        levels: SailingLevels?
    ) -> Band? {
        guard canHoldByBand, backend == .firmwareRange, phase == .holding, let levels else {
            heldLevel = nil
            heldResumeLevel = nil
            return nil
        }
        let atTheBattery = min(batteryLevel, levels.limit)
        var held: Int
        if let heldLevel, !startedAfresh, heldResumeLevel == levels.resumeLevel, heldLevel <= levels.limit {
            held = max(heldLevel, atTheBattery)
        } else {
            held = atTheBattery
        }
        heldLevel = held
        heldResumeLevel = levels.resumeLevel
        // At the limit the real band holds. Kept above the resume level as well: the phase holds
        // only at or above it, but a band is never handed over inverted.
        guard held < levels.limit, held >= levels.resumeLevel,
              FirmwareChargeRange.canHold(limit: held)
        else { return nil }
        let lower = levels.resumeLevel < held ? levels.resumeLevel : held - 1
        return Band(limit: held, resumeLevel: max(FirmwareChargeRange.minimumLowerBound, lower))
    }

    /// Whether the hold keeps an upper bound other than the person's `limit` — BatFi's own
    /// short-lived value, like a frozen limit elsewhere.
    public func keepsAValueOtherThan(_ limit: Int) -> Bool {
        heldLevel.map { $0 != limit } ?? false
    }

    /// Records how the held band this pass asked for went out. Not called for a failed apply,
    /// which says nothing. A held band sent as the one-value call is not in force — the firmware
    /// was handed a narrow band under it instead — so the hold ends here.
    public mutating func recordApply(of band: Band?, wentOutAsRange: Bool) {
        guard band != nil, !wentOutAsRange else { return }
        canHoldByBand = false
        heldLevel = nil
        heldResumeLevel = nil
    }
}
