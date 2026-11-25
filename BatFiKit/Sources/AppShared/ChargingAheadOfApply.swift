//
//  ChargingAheadOfApply.swift
//
//
//  Showing a change of the limit before the apply that makes it has returned.
//
//  `ChargingManager` publishes its mode only after it has applied the limit, and on macOS 27
//  an apply of a sub-80 limit waits up to 45 s for powerd. A raise — "Resume Charging" from a
//  pause at 65%, the slider moved from 60 to 70 — then went on showing the old state for all
//  of it, and a lowering under a charging battery — the slider from 75 to 70 at 73% — showed
//  charging, and both announced it once the 2 s debounce ran out. The owner wants every
//  change shown at once, so the pass publishes the mode the change will put the battery in
//  before the apply: charging on a raise over it, held on a lowering under it. On Apple's
//  charge limit neither command writes anything to the SMC — powerd owns the charging
//  decision — so they cost nothing but the mode they publish, which is the one the pass
//  would publish after the apply anyway.
//
//  Here rather than in `ChargingManager` because `AppCore` has no test target.
//

import Foundation
import Shared

public enum ChargingAheadOfApply {
    /// The mode the pass publishes before it applies `requested`, or nil for none.
    ///
    /// - Parameters:
    ///   - lastApplied: the limit the last successful apply returned
    ///     (`ChargeLimitRaiseWindow.lastAppliedLimit`).
    ///   - floor: the floor this Mac has been seen to apply a sub-80 request at — 80 where
    ///     macOS has no path below it — or nil where none was seen (`learnedFloor`). The
    ///     request is judged at what the apply will put in force (`willApply`): 70 over an
    ///     applied 80 is no change at all, and there is no hold at 70 to show over a battery at
    ///     75 that goes on charging to 80.
    ///   - overrideInForce: the override published now. An inhibit is a pause, never a
    ///     charge; a plain override lowered under the battery is BatFi's own discharge, which
    ///     the pass decides after the apply.
    ///   - passIsStale: the pass worked its request out under an override that is no longer
    ///     the one in force. A "Charge to 100%" read before Stop Override is not asked for.
    ///   - appliesAreFailing: the last apply failed, so a change is not known to land.
    public static func modeAhead(
        backend: ChargeBackend?,
        chargerConnected: Bool,
        lastApplied: Int?,
        requested: Int,
        floor: Int?,
        batteryLevel: Int,
        overrideInForce: UserTempChargingMode?,
        passIsStale: Bool,
        appliesAreFailing: Bool
    ) -> ChargingMode? {
        guard HotBatteryHold.applies(to: backend),
              chargerConnected,
              !passIsStale,
              !appliesAreFailing,
              let lastApplied
        else { return nil }
        let willApply = willApply(requested: requested, floor: floor)
        if willApply > lastApplied, batteryLevel < willApply, overrideInForce?.isInhibit != true {
            return .charging
        }
        if willApply < lastApplied, batteryLevel >= willApply, overrideInForce == nil || overrideInForce?.isInhibit == true {
            return .inhibit
        }
        return nil
    }

    /// The limit an apply of `requested` will put in force, as far as is known before it.
    ///
    /// From 80 up, the request: the helper reports it back as applied, and the mode decision
    /// after the apply judges the battery against that. Below 80, the floor where one has been
    /// seen, else the request: the first sub-80 request after a launch on a Mac with a floor is
    /// judged as asked — one miss per process, since nothing the app can read up front says
    /// whether macOS has a path below 80 — and its apply teaches the floor.
    public static func willApply(requested: Int, floor: Int?) -> Int {
        guard requested < 80 else { return requested }
        return max(requested, floor ?? requested)
    }

    /// The floor after an apply of `requested` returned `applied`.
    ///
    /// Learned only from a request below 80: rounding from 80 up — 87 applied as 90 — is the
    /// step, not a floor, and learned as one it hid a later 90-to-75 lowering at 82%. A sub-80
    /// request applied as asked clears it.
    public static func learnedFloor(previous: Int?, requested: Int, applied: Int) -> Int? {
        guard requested < 80 else { return previous }
        return applied > requested ? applied : nil
    }

    /// What ending `ending` publishes at the click — see `OverrideEnd`.
    ///
    /// The state the pass after the click will decide, published with the end so the left-over
    /// pause is never shown on its own, and so the pass changes nothing the user sees: the
    /// owner wants every change shown at once, with no flip back. Worked out by the rules the
    /// pass applies, at the limit the apply will put in force (`willApply`), on every backend
    /// that can hold a pause.
    ///
    /// - The discharge a discharge pause replaced — "Run on Battery", a Shortcuts limit — is put
    ///   back only for "Resume Discharging" (`restoringPausedOverride`). Stop Override, from the
    ///   hotkey or Shortcuts, ends with no override in force, which automations rely on. A
    ///   restored discharge runs where the pass would run it: above its own target, with the
    ///   lid open or sleep disabled — always under Apple's limit, where a manual discharge
    ///   disables sleep.
    /// - Otherwise below the limit resumed to, charging; above it under Apple's charge limit,
    ///   macOS draining to it — held while powerd adopts the lowering (`DischargeResumeHold`);
    ///   above it on the inhibit backends, BatFi's own discharge where the pass would run one;
    ///   else held. Below the limit but at or above the sailing resume level, held — and that
    ///   hold, or one at the limit while sailing, is published with its resume level. A restored
    ///   override is judged the same way against its own levels (`restoredSailingResumeLevel`).
    ///
    /// Nothing is published ahead where it is not known: a plain override, the charger out,
    /// charging not managed, a backend that cannot hold a pause or is not known yet, or — under
    /// Apple's limit — applies that are failing, so the change may not land.
    public static func onEndingOverride(
        _ ending: UserTempChargingMode,
        restoringPausedOverride: Bool,
        conditions c: ResumeConditions
    ) -> OverrideEnd {
        let restoring = restoringPausedOverride ? ending.overrideToResume : nil
        let nothingAhead = OverrideEnd(restoring: restoring)
        guard ending.isInhibit,
              c.chargerConnected,
              c.isManagingCharging,
              let backend = c.backend,
              backend.canHoldChargeAtCurrentLevel
        else { return nothingAhead }
        let onAppleLimit = HotBatteryHold.applies(to: backend)
        if onAppleLimit, c.appliesAreFailing { return nothingAhead }
        // The hot-battery cutout inhibits ahead of every other arm on the inhibit backends.
        // Under Apple's limit it is part of the resumed limit instead.
        if !onAppleLimit, c.batteryIsHot {
            return OverrideEnd(restoring: restoring, mode: .inhibit)
        }

        if let restoring {
            let inForce = onAppleLimit ? willApply(requested: restoring.limit, floor: c.floor) : restoring.limit
            if c.batteryLevel > restoring.limit, onAppleLimit || c.lidOpenOrSleepDisabled {
                return OverrideEnd(restoring: restoring, mode: .forceDischarge)
            }
            // The restored limit sails against its own levels (the main screen's distance below it): inside its range,
            // and at or above it where nothing drains, the pass after the click holds.
            if c.batteryLevel < inForce {
                if let resume = c.restoredSailingResumeLevel, c.batteryLevel >= resume {
                    return OverrideEnd(restoring: restoring, mode: .inhibit, sailingResumeLevel: resume)
                }
                return OverrideEnd(restoring: restoring, mode: .charging)
            }
            return OverrideEnd(restoring: restoring, mode: .inhibit, sailingResumeLevel: c.restoredSailingResumeLevel)
        }

        let inForce = onAppleLimit ? willApply(requested: c.resumedLimit, floor: c.floor) : c.resumedLimit
        if c.batteryLevel < inForce {
            // Inside the sailing range the pass holds rather than charges.
            if let resume = c.sailingResumeLevel, c.batteryLevel >= resume {
                return OverrideEnd(mode: .inhibit, sailingResumeLevel: resume)
            }
            return OverrideEnd(mode: .charging)
        }
        if onAppleLimit {
            // At or above the limit a fresh sailing phase holds there, named as at the limit.
            return OverrideEnd(
                mode: .inhibit,
                systemIsDischargingToLimit: c.batteryLevel > inForce,
                sailingResumeLevel: c.sailingResumeLevel
            )
        }
        let discharges = c.batteryLevel > inForce && c.allowDischarging && c.lidOpenOrSleepDisabled && !c.computerIsAsleep
        // At the limit a fresh sailing phase holds, and the pass names the hold there too.
        return discharges
            ? OverrideEnd(mode: .forceDischarge)
            : OverrideEnd(mode: .inhibit, sailingResumeLevel: c.sailingResumeLevel)
    }
}

/// What the pass after a click that ends an override reads, as the click sees it — the inputs
/// `ChargingAheadOfApply.onEndingOverride` decides the published state from.
public struct ResumeConditions: Equatable, Sendable {
    public var backend: ChargeBackend?
    public var chargerConnected: Bool
    public var batteryLevel: Int
    /// The limit the pass after the click requests with no override: the user's, an
    /// automation's, a hot battery's or the charge-to-full hold's, by the pass's own rule.
    public var resumedLimit: Int
    /// The floor this Mac applies a sub-80 request at, or nil where none was seen.
    public var floor: Int?
    /// The last apply failed (Apple's charge limit).
    public var appliesAreFailing: Bool
    /// Licensed and "Manage charging" on — otherwise the pass hands charging back.
    public var isManagingCharging: Bool
    /// "Allow discharging" (`allowDischargingFullBattery`).
    public var allowDischarging: Bool
    /// The lid is open, or sleep is disabled for a discharge.
    public var lidOpenOrSleepDisabled: Bool
    public var computerIsAsleep: Bool
    /// The hot-battery cutout fires this pass.
    public var batteryIsHot: Bool
    /// The level below which sailing resumes charging, where the pass after the click would
    /// sail; nil where it would not.
    public var sailingResumeLevel: Int?
    /// The level below which sailing resumes charging under the override "Resume Discharging"
    /// puts back — a temporary limit sails at the main screen's distance below it — where the pass after the click would
    /// sail against it; nil where it would not, or where nothing is restored.
    public var restoredSailingResumeLevel: Int?

    public init(
        backend: ChargeBackend?,
        chargerConnected: Bool,
        batteryLevel: Int,
        resumedLimit: Int,
        floor: Int? = nil,
        appliesAreFailing: Bool = false,
        isManagingCharging: Bool = true,
        allowDischarging: Bool = false,
        lidOpenOrSleepDisabled: Bool = true,
        computerIsAsleep: Bool = false,
        batteryIsHot: Bool = false,
        sailingResumeLevel: Int? = nil,
        restoredSailingResumeLevel: Int? = nil
    ) {
        self.backend = backend
        self.chargerConnected = chargerConnected
        self.batteryLevel = batteryLevel
        self.resumedLimit = resumedLimit
        self.floor = floor
        self.appliesAreFailing = appliesAreFailing
        self.isManagingCharging = isManagingCharging
        self.allowDischarging = allowDischarging
        self.lidOpenOrSleepDisabled = lidOpenOrSleepDisabled
        self.computerIsAsleep = computerIsAsleep
        self.batteryIsHot = batteryIsHot
        self.sailingResumeLevel = sailingResumeLevel
        self.restoredSailingResumeLevel = restoredSailingResumeLevel
    }
}

/// What the click that ends an override publishes with the end, in one publish.
public struct OverrideEnd: Equatable, Sendable {
    /// The override put in its place: the discharge a discharge pause resumes, or nil.
    public let restoring: UserTempChargingMode?
    /// The mode published with it, or nil to keep the published one for the pass to decide.
    public let mode: ChargingMode?
    /// macOS draining to the limit again, or nil to keep the published flag.
    public let systemIsDischargingToLimit: Bool?
    /// The sailing hold the end goes back to. Read only with a `mode`: an end that publishes a
    /// mode publishes this with it, nil clearing a level published earlier; one with no mode
    /// keeps the published level for the pass to decide. A pause publishes no hold, so without
    /// this the click would show a plain inhibit until the pass after it named the hold.
    public let sailingResumeLevel: Int?

    public init(
        restoring: UserTempChargingMode? = nil,
        mode: ChargingMode? = nil,
        systemIsDischargingToLimit: Bool? = nil,
        sailingResumeLevel: Int? = nil
    ) {
        self.restoring = restoring
        self.mode = mode
        self.systemIsDischargingToLimit = systemIsDischargingToLimit
        self.sailingResumeLevel = sailingResumeLevel
    }

    /// The override cleared, and nothing else published.
    public static let plain = OverrideEnd()

    /// The end of a pause whose inhibit writes kept failing: the discharge it replaced is put
    /// back, as Resume Discharging would, and the pass decides the mode.
    public static func afterFailedInhibitWrites(ending: UserTempChargingMode) -> OverrideEnd {
        OverrideEnd(restoring: ending.overrideToResume)
    }
}
