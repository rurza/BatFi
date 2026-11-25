//
//  ResumeAtTheClickTests.swift
//  BatFi
//
//  What ending a pause publishes at the click, on every backend: the state the pass after it
//  will decide, judged at the limit the apply will put in force — so nothing flips back — and
//  nothing ahead where that is not known. Only "Resume Discharging" in the menu puts back the
//  discharge a pause replaced; Stop Override, from the hotkey or Shortcuts, ends with no
//  override in force.
//

import Foundation
import L10n
import Shared
import Testing

@testable import AppShared

@Suite struct ResumeAtTheClickTests {
    private let dischargePause = UserTempChargingMode(limit: 85, isInhibit: true, pausesDischarge: true)
    private let pausedRunOnBattery = UserTempChargingMode(limit: 85, isInhibit: true, pausesDischarge: true, resumesOverrideLimit: 0)
    private let chargingPause = UserTempChargingMode(limit: 65, isInhibit: true)

    private func end(
        _ ending: UserTempChargingMode,
        restoring: Bool = true,
        backend: ChargeBackend? = .systemChargeLimit,
        level: Int,
        resumedLimit: Int = 80,
        floor: Int? = nil,
        appliesAreFailing: Bool = false,
        isManagingCharging: Bool = true,
        allowDischarging: Bool = false,
        lidOpenOrSleepDisabled: Bool = true,
        computerIsAsleep: Bool = false,
        batteryIsHot: Bool = false,
        sailingResumeLevel: Int? = nil,
        restoredSailingResumeLevel: Int? = nil
    ) -> OverrideEnd {
        ChargingAheadOfApply.onEndingOverride(
            ending,
            restoringPausedOverride: restoring,
            conditions: ResumeConditions(
                backend: backend,
                chargerConnected: true,
                batteryLevel: level,
                resumedLimit: resumedLimit,
                floor: floor,
                appliesAreFailing: appliesAreFailing,
                isManagingCharging: isManagingCharging,
                allowDischarging: allowDischarging,
                lidOpenOrSleepDisabled: lidOpenOrSleepDisabled,
                computerIsAsleep: computerIsAsleep,
                batteryIsHot: batteryIsHot,
                sailingResumeLevel: sailingResumeLevel,
                restoredSailingResumeLevel: restoredSailingResumeLevel
            )
        )
    }

    // MARK: - Judged at the applied limit (Apple's charge limit)

    /// Limit 70 applied as 80, paused at 80: macOS holds at 80, it does not drain.
    @Test func aRequestUnderTheFloorIsJudgedAtTheFloor() {
        #expect(end(dischargePause, level: 80, resumedLimit: 70, floor: 80) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: false))
        #expect(end(dischargePause, level: 85, resumedLimit: 70, floor: 80) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
        #expect(end(chargingPause, level: 75, resumedLimit: 70, floor: 80) == OverrideEnd(mode: .charging))
    }

    /// A change that may not land is not shown ahead.
    @Test func failingAppliesPublishNothingAhead() {
        #expect(end(dischargePause, level: 95, appliesAreFailing: true) == .plain)
        #expect(end(chargingPause, level: 65, appliesAreFailing: true) == .plain)
    }

    /// The discharge Run on Battery runs is BatFi's own, judged at the request, not the limit.
    @Test func aRestoredDischargeIsJudgedAtItsOwnTarget() {
        #expect(end(pausedRunOnBattery, level: 85, floor: 80) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .forceDischarge))
    }

    // MARK: - Only Resume Discharging restores

    /// Stop Override — the hotkey, Shortcuts — ends with no override in force; automations
    /// rely on that.
    @Test func stopOverrideDoesNotRestoreThePausedDischarge() {
        #expect(end(pausedRunOnBattery, restoring: false, level: 85).restoring == nil)
        #expect(end(pausedRunOnBattery, restoring: false, level: 85) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
        #expect(end(pausedRunOnBattery, restoring: false, backend: .chte, level: 85).restoring == nil)
    }

    @Test func resumeDischargingRestoresIt() {
        #expect(end(pausedRunOnBattery, level: 85).restoring == UserTempChargingMode(limit: 0))
    }

    // MARK: - The inhibit backends, at the click

    @Test func resumingBelowTheLimitIsCharging() {
        #expect(end(chargingPause, backend: .chte, level: 65) == OverrideEnd(mode: .charging))
        #expect(end(dischargePause, backend: .legacyCH0BC, level: 75) == OverrideEnd(mode: .charging))
    }

    /// BatFi's own discharge resumes where the pass would run it: allowed, lid open or sleep
    /// disabled, awake.
    @Test func resumingAboveTheLimitIsBatFisDischargeWhereThePassWouldRunIt() {
        #expect(end(dischargePause, backend: .chte, level: 85, allowDischarging: true) == OverrideEnd(mode: .forceDischarge))
        #expect(end(dischargePause, backend: .chte, level: 85, allowDischarging: false) == OverrideEnd(mode: .inhibit))
        #expect(end(dischargePause, backend: .chte, level: 85, allowDischarging: true, lidOpenOrSleepDisabled: false) == OverrideEnd(mode: .inhibit))
        #expect(end(dischargePause, backend: .chte, level: 85, allowDischarging: true, computerIsAsleep: true) == OverrideEnd(mode: .inhibit))
        #expect(end(dischargePause, backend: .chte, level: 80, allowDischarging: true) == OverrideEnd(mode: .inhibit))
    }

    @Test func aRestoredDischargeNeedsTheLidOpenOrSleepDisabled() {
        #expect(end(pausedRunOnBattery, backend: .chte, level: 85) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .forceDischarge))
        #expect(end(pausedRunOnBattery, backend: .chte, level: 85, lidOpenOrSleepDisabled: false) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .inhibit))
    }

    /// The hot-battery cutout inhibits ahead of everything on these backends.
    @Test func aHotBatteryIsHeld() {
        #expect(end(chargingPause, backend: .chte, level: 65, batteryIsHot: true) == OverrideEnd(mode: .inhibit))
        #expect(end(pausedRunOnBattery, backend: .chte, level: 85, batteryIsHot: true) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .inhibit))
    }

    // MARK: - Nothing ahead where nothing is decided

    @Test func nothingAheadWhileChargingIsNotManaged() {
        #expect(end(chargingPause, backend: .chte, level: 65, isManagingCharging: false) == .plain)
        #expect(end(pausedRunOnBattery, backend: .chte, level: 85, isManagingCharging: false) == OverrideEnd(restoring: UserTempChargingMode(limit: 0)))
    }

    @Test func nothingAheadWhereNothingCanHold() {
        #expect(end(chargingPause, backend: .firmwareRange, level: 65) == .plain)
        #expect(end(chargingPause, backend: nil, level: 65) == .plain)
    }

    @Test func aPlainOverrideEndsWithNothingAhead() {
        #expect(end(UserTempChargingMode(limit: 100), backend: .chte, level: 65) == .plain)
    }

    // MARK: - A pause ended by failing inhibit writes

    @Test func failingWritesPutThePausedDischargeBack() {
        #expect(OverrideEnd.afterFailedInhibitWrites(ending: pausedRunOnBattery) == OverrideEnd(restoring: UserTempChargingMode(limit: 0)))
        #expect(OverrideEnd.afterFailedInhibitWrites(ending: chargingPause) == .plain)
        #expect(OverrideEnd.afterFailedInhibitWrites(ending: dischargePause) == .plain)
    }

    // MARK: - No flip after the click

    /// The click on an inhibit backend publishes what the pass decides, so the pass after it
    /// changes nothing the user sees, and one banner is posted.
    @Test func theClickMatchesThePassOnTheInhibitBackends() {
        let state = AppChargingMode(mode: .inhibit, userTempOverride: dischargePause, chargerConnected: true)
        let end = end(dischargePause, backend: .chte, level: 85, allowDischarging: true)
        let atClick = state.endingOverride(dischargePause, with: end)
        let afterPass = AppChargingMode(mode: .forceDischarge, userTempOverride: nil, chargerConnected: true)
        #expect(atClick.stateDescription == afterPass.stateDescription)
        #expect(BatteryIndicatorMode(appChargingMode: atClick) == BatteryIndicatorMode(appChargingMode: afterPass))
        #expect(atClick.stateDescription == L10n.AppChargingMode.State.Title.forceDischarge)
    }

    // MARK: - Sailing

    /// Ending a pause inside the sailing range goes back to the hold, not to charging.
    /// Published with the resume level, so the click shows the hold itself rather than a plain
    /// inhibit until the next pass names it.
    @Test func endingAPauseInsideTheSailingRangeShowsTheHold() {
        #expect(end(chargingPause, backend: .chte, level: 75, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit, sailingResumeLevel: 70))
        #expect(end(chargingPause, backend: .chte, level: 70, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit, sailingResumeLevel: 70))
    }

    /// At the limit the pass holds with the resume level named, so the click does too.
    @Test func endingAPauseAtTheLimitWhileSailingShowsTheHold() {
        #expect(end(chargingPause, backend: .chte, level: 80, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit, sailingResumeLevel: 70))
    }

    /// Discharge above the limit, the hot-battery cutout and a resumed discharge all outrank
    /// sailing, and none of them is the hold.
    @Test func whatOutranksSailingIsShownWithoutTheHold() {
        #expect(end(chargingPause, backend: .chte, level: 85, resumedLimit: 80, allowDischarging: true, sailingResumeLevel: 70) == OverrideEnd(mode: .forceDischarge))
        #expect(end(chargingPause, backend: .chte, level: 75, resumedLimit: 80, batteryIsHot: true, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit))
        #expect(end(pausedRunOnBattery, backend: .chte, level: 75, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .forceDischarge))
    }

    @Test func endingAPauseBelowTheResumeLevelShowsCharging() {
        #expect(end(chargingPause, backend: .chte, level: 65, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .charging))
    }

    /// Under Apple's limit the pass after the click holds at the limit too, and names the hold
    /// there; a battery above it is drained to it, the drain told as it is with sailing off.
    @Test func endingAPauseUnderApplesLimitWhileSailingShowsTheHold() {
        #expect(end(chargingPause, level: 75, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit, sailingResumeLevel: 70))
        #expect(end(chargingPause, level: 80, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: false, sailingResumeLevel: 70))
        #expect(end(chargingPause, level: 85, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true, sailingResumeLevel: 70))
        #expect(end(chargingPause, level: 65, resumedLimit: 80, sailingResumeLevel: 70) == OverrideEnd(mode: .charging))
    }

    /// "Resume Discharging" over a paused Shortcuts limit of 60 puts that limit back, and a
    /// temporary limit sails like a rule's: 50–60 under a 70–80 range. The pass after the click
    /// starts a fresh phase against those levels, so the click is judged against them too —
    /// the restored limit's own levels, not the ones with no override.
    private let pausedShortcutsDischarge = UserTempChargingMode(limit: 66, isInhibit: true, pausesDischarge: true, resumesOverrideLimit: 60)

    @Test func endingAPauseIntoARestoredLimitInsideItsSailingRangeShowsTheHold() {
        let restored = UserTempChargingMode(limit: 60)
        for backend: ChargeBackend in [.chte, .systemChargeLimit] {
            #expect(end(pausedShortcutsDischarge, backend: backend, level: 57, sailingResumeLevel: 70, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .inhibit, sailingResumeLevel: 50))
            #expect(end(pausedShortcutsDischarge, backend: backend, level: 50, sailingResumeLevel: 70, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .inhibit, sailingResumeLevel: 50))
            // At the restored limit the fresh phase holds there, named as at the limit.
            #expect(end(pausedShortcutsDischarge, backend: backend, level: 60, sailingResumeLevel: 70, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .inhibit, sailingResumeLevel: 50))
        }
        // Above it with the lid closed on an inhibit backend, nothing drains: the hold, named.
        #expect(end(pausedShortcutsDischarge, backend: .chte, level: 66, lidOpenOrSleepDisabled: false, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .inhibit, sailingResumeLevel: 50))
    }

    @Test func endingAPauseIntoARestoredLimitBelowItsResumeLevelShowsCharging() {
        let restored = UserTempChargingMode(limit: 60)
        #expect(end(pausedShortcutsDischarge, backend: .chte, level: 49, sailingResumeLevel: 70, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .charging))
        // With no sailing for the restored limit, as before.
        #expect(end(pausedShortcutsDischarge, backend: .chte, level: 57) == OverrideEnd(restoring: restored, mode: .charging))
    }

    /// The restored discharge outranks sailing: drained to its own target, with no hold named.
    @Test func aRestoredDischargeAboveItsLimitIsNotTheHold() {
        let restored = UserTempChargingMode(limit: 60)
        #expect(end(pausedShortcutsDischarge, backend: .chte, level: 66, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .forceDischarge))
        #expect(end(pausedShortcutsDischarge, level: 66, restoredSailingResumeLevel: 50) == OverrideEnd(restoring: restored, mode: .forceDischarge))
    }
}
