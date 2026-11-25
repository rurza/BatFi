//
//  DischargePauseTests.swift
//  BatFi
//
//  "Pause Discharging": the pause, offered while the battery discharges on the charger —
//  macOS draining it to the limit, or BatFi's own discharge — held exactly as "Inhibit
//  Charging" holds charge, and told as what it pauses. "Resume Discharging" ends it, and puts
//  back the discharge it paused. Shown at the click, both ways, and held while powerd adopts
//  the limit.
//

import Foundation
import L10n
import Shared
import Testing

@testable import AppShared

@Suite struct DischargePauseTests {
    private func mode(
        _ mode: ChargingMode,
        override: UserTempChargingMode? = nil,
        chargerConnected: Bool = true,
        draining: Bool = false,
        toppingUp: Bool = false,
        holdingBelow: Bool = false
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: override,
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: draining,
            systemIsHoldingBelowLimit: holdingBelow,
            systemIsChargingPastLimit: toppingUp
        )
    }

    private func percent(_ limit: Int) -> String {
        percentageFormatter.string(from: Double(limit) / 100 as NSNumber)!
    }

    private let macOSDrain = AppChargingMode(
        mode: .inhibit,
        userTempOverride: nil,
        chargerConnected: true,
        systemIsDischargingToLimit: true
    )

    // MARK: - What is offered

    @Test func chargingIsPausedAsCharging() {
        for backend: ChargeBackend? in [.systemChargeLimit, .chte, .legacyCH0BC, nil] {
            #expect(ManualInhibit.pauseOffered(for: mode(.charging), backend: backend) == .charging)
            #expect(StatusMenuCommands.pauseTitle(mode: mode(.charging), backend: backend) == L10n.Menu.Label.inhibitCharging)
        }
    }

    /// The owner's case: on the charger at 100%, macOS draining to an 80% limit.
    @Test func macOSDrainingToTheLimitIsPausedAsDischarging() {
        #expect(ManualInhibit.pauseOffered(for: macOSDrain, backend: .systemChargeLimit) == .discharging)
        #expect(StatusMenuCommands.showsInhibitCharging(mode: macOSDrain, backend: .systemChargeLimit))
        #expect(StatusMenuCommands.pauseTitle(mode: macOSDrain, backend: .systemChargeLimit) == L10n.Menu.Label.pauseDischarging)
    }

    /// BatFi's own discharge used to offer "Inhibit Charging".
    @Test func batFisOwnDischargeIsPausedAsDischarging() {
        for backend: ChargeBackend? in [.systemChargeLimit, .chte, .legacyCH0BC, nil] {
            #expect(ManualInhibit.pauseOffered(for: mode(.forceDischarge), backend: backend) == .discharging)
            #expect(StatusMenuCommands.pauseTitle(mode: mode(.forceDischarge), backend: backend) == L10n.Menu.Label.pauseDischarging)
        }
    }

    /// Nothing can stop a battery powering the Mac.
    @Test func nothingIsOfferedOffTheCharger() {
        #expect(ManualInhibit.pauseOffered(for: mode(.forceDischarge, chargerConnected: false), backend: .chte) == nil)
        #expect(ManualInhibit.pauseOffered(for: mode(.inhibit, chargerConnected: false, draining: true), backend: .systemChargeLimit) == nil)
        #expect(ManualInhibit.pauseOffered(for: mode(.charging, chargerConnected: false), backend: .chte) == nil)
    }

    @Test func theBackendRuleIsInhibitChargingsRule() {
        for backend in [ChargeBackend.firmwareRange, .unsupported] {
            #expect(ManualInhibit.pauseOffered(for: macOSDrain, backend: backend) == nil)
            #expect(ManualInhibit.pauseOffered(for: mode(.forceDischarge), backend: backend) == nil)
        }
    }

    /// A hold is already a pause, and a calibration top-up is macOS's, not BatFi's to pause.
    @Test func theOtherHeldStatesOfferNothing() {
        #expect(ManualInhibit.pauseOffered(for: mode(.inhibit), backend: .systemChargeLimit) == nil)
        #expect(ManualInhibit.pauseOffered(for: mode(.inhibit, holdingBelow: true), backend: .systemChargeLimit) == nil)
        #expect(ManualInhibit.pauseOffered(for: mode(.inhibit, toppingUp: true), backend: .systemChargeLimit) == nil)
        #expect(ManualInhibit.pauseOffered(for: mode(.initial), backend: .systemChargeLimit) == nil)
    }

    @Test func nothingIsOfferedWhileAPauseIsArmed() {
        let paused = UserTempChargingMode(limit: 95, isInhibit: true, pausesDischarge: true)
        #expect(ManualInhibit.pauseOffered(for: mode(.inhibit, override: paused, draining: true), backend: .systemChargeLimit) == nil)
        #expect(ManualInhibit.pauseOffered(for: mode(.forceDischarge, override: paused), backend: .chte) == nil)
    }

    /// "Run on Battery" is a plain override, and pausing it is the point.
    @Test func aDischargeUnderAPlainOverrideIsOffered() {
        let runOnBattery = mode(.forceDischarge, override: UserTempChargingMode(limit: 0))
        #expect(ManualInhibit.pauseOffered(for: runOnBattery, backend: .systemChargeLimit) == .discharging)
    }

    // MARK: - The override it arms

    /// Held the way Inhibit Charging holds: frozen at the level, rounded down from 80 up.
    @Test func underAppleChargeLimitTheFrozenLimitRoundsDown() {
        let at100 = ManualInhibit.pause(for: macOSDrain, batteryLevel: 100, backend: .systemChargeLimit)
        #expect(at100 == UserTempChargingMode(limit: 100, isInhibit: true, pausesDischarge: true))
        let at97 = ManualInhibit.pause(for: macOSDrain, batteryLevel: 97, backend: .systemChargeLimit)
        #expect(at97?.limit == 95)
        #expect(at97?.pausesDischarge == true)
        #expect(at97?.resumesOverrideLimit == nil)
    }

    @Test func theInhibitBackendsHoldTheExactLevel() {
        let paused = ManualInhibit.pause(for: mode(.forceDischarge), batteryLevel: 87, backend: .chte)
        #expect(paused == UserTempChargingMode(limit: 87, isInhibit: true, pausesDischarge: true))
    }

    @Test func aChargingPauseIsUnchanged() {
        #expect(ManualInhibit.pause(for: mode(.charging), batteryLevel: 87, backend: .systemChargeLimit) == ManualInhibit.override(batteryLevel: 87, backend: .systemChargeLimit))
        #expect(ManualInhibit.pause(for: mode(.charging), batteryLevel: 63, backend: .chte) == UserTempChargingMode(limit: 63, isInhibit: true))
    }

    /// The discharge "Run on Battery" was doing is what Resume Discharging resumes.
    @Test func aPausedPlainOverrideIsRememberedToResume() {
        let runOnBattery = mode(.forceDischarge, override: UserTempChargingMode(limit: 0))
        let paused = ManualInhibit.pause(for: runOnBattery, batteryLevel: 61, backend: .chte)
        #expect(paused?.resumesOverrideLimit == 0)
        #expect(paused?.overrideToResume == UserTempChargingMode(limit: 0))
    }

    /// An unknown backend arms the plain override it always has; it cannot be told apart later.
    @Test func anUnknownBackendArmsAPlainOverride() {
        #expect(ManualInhibit.pause(for: mode(.forceDischarge), batteryLevel: 61, backend: nil) == UserTempChargingMode(limit: 61))
    }

    @Test func nothingIsArmedWhereNothingIsOffered() {
        #expect(ManualInhibit.pause(for: mode(.inhibit), batteryLevel: 80, backend: .systemChargeLimit) == nil)
        #expect(ManualInhibit.pause(for: mode(.forceDischarge, chargerConnected: false), batteryLevel: 80, backend: .chte) == nil)
    }

    @Test func whatIsPausedIsPartOfEquality() {
        #expect(UserTempChargingMode(limit: 80, isInhibit: true) != UserTempChargingMode(limit: 80, isInhibit: true, pausesDischarge: true))
        #expect(
            UserTempChargingMode(limit: 80, isInhibit: true, pausesDischarge: true)
                != UserTempChargingMode(limit: 80, isInhibit: true, pausesDischarge: true, resumesOverrideLimit: 0)
        )
    }

    @Test func onlyAnInhibitPausesADischarge() {
        let plain = UserTempChargingMode(limit: 80, isInhibit: false, pausesDischarge: true, resumesOverrideLimit: 0)
        #expect(!plain.pausesDischarge)
        #expect(plain.resumesOverrideLimit == nil)
    }

    // MARK: - What the user is told

    private let paused = UserTempChargingMode(limit: 95, isInhibit: true, pausesDischarge: true)

    @Test func aDischargePauseIsTitledDischargingPausedWhateverTheMode() {
        for state in [ChargingMode.charging, .inhibit, .forceDischarge] {
            let armed = mode(state, override: paused, draining: true)
            #expect(armed.stateDescription == L10n.AppChargingMode.State.Title.dischargingPausedAt(percent(95)))
            #expect(armed.stateDescription(chargeLimitFraction: 0.8) == L10n.AppChargingMode.State.Description.dischargingPaused)
        }
    }

    /// The pause, not the discharge that is still running while powerd adopts the limit.
    @Test func aDischargePauseDrawsThePauseWhateverTheMode() {
        for state in [ChargingMode.charging, .inhibit, .forceDischarge] {
            #expect(BatteryIndicatorMode(appChargingMode: mode(state, override: paused, draining: true)) == .inhibited)
        }
    }

    @Test func aDischargePauseIsAnnouncedAtOnce() {
        #expect(ModeChangeAnnouncement.consideration(of: mode(.inhibit, override: paused, draining: true), manageCharging: true) == .announce)
    }

    @Test func aChargingPauseKeepsItsWords() {
        let charging = mode(.charging, override: UserTempChargingMode(limit: 77, isInhibit: true))
        #expect(charging.stateDescription == L10n.AppChargingMode.State.Title.chargingPausedAt(percent(77)))
        #expect(charging.stateDescription(chargeLimitFraction: 0.8) == L10n.AppChargingMode.State.Description.chargingPaused)
    }

    // MARK: - Menu

    @Test func aDischargePauseIsEndedWithResumeDischarging() {
        #expect(StatusMenuCommands.stopOverrideTitle(for: paused) == L10n.Menu.Label.resumeDischarging)
        #expect(StatusMenuCommands.stopOverrideTitle(for: UserTempChargingMode(limit: 77, isInhibit: true)) == L10n.Menu.Label.resumeCharging)
        #expect(StatusMenuCommands.stopOverrideTitle(for: UserTempChargingMode(limit: 77)) == L10n.Menu.Label.stopOverride)
    }

    /// Paused at 100% — the owner's case — is no "Charge to 100%", and has its Resume button.
    @Test func aPauseAtAFullBatteryIsNotChargeToFull() {
        let atFull = UserTempChargingMode(limit: 100, isInhibit: true, pausesDischarge: true)
        #expect(StatusMenuCommands.showsStopOverride(for: atFull))
        #expect(!StatusMenuCommands.isChargeToFull(atFull))
        #expect(StatusMenuCommands.isChargeToFull(UserTempChargingMode(limit: 100)))
        #expect(!StatusMenuCommands.showsStopOverride(for: UserTempChargingMode(limit: 100)))
    }

    @Test func aPauseAtAnEmptyBatteryIsNotRunOnBattery() {
        #expect(!StatusMenuCommands.isRunOnBattery(UserTempChargingMode(limit: 0, isInhibit: true)))
        #expect(StatusMenuCommands.isRunOnBattery(UserTempChargingMode(limit: 0)))
        #expect(!StatusMenuCommands.isRunOnBattery(nil))
    }

    // MARK: - Resume Discharging at the click

    private func end(
        _ ending: UserTempChargingMode,
        restoring: Bool = true,
        backend: ChargeBackend? = .systemChargeLimit,
        chargerConnected: Bool = true,
        level: Int = 95,
        resumedLimit: Int = 80,
        floor: Int? = nil,
        appliesAreFailing: Bool = false,
        isManagingCharging: Bool = true,
        allowDischarging: Bool = false,
        lidOpenOrSleepDisabled: Bool = true,
        computerIsAsleep: Bool = false,
        batteryIsHot: Bool = false
    ) -> OverrideEnd {
        ChargingAheadOfApply.onEndingOverride(
            ending,
            restoringPausedOverride: restoring,
            conditions: ResumeConditions(
                backend: backend,
                chargerConnected: chargerConnected,
                batteryLevel: level,
                resumedLimit: resumedLimit,
                floor: floor,
                appliesAreFailing: appliesAreFailing,
                isManagingCharging: isManagingCharging,
                allowDischarging: allowDischarging,
                lidOpenOrSleepDisabled: lidOpenOrSleepDisabled,
                computerIsAsleep: computerIsAsleep,
                batteryIsHot: batteryIsHot
            )
        )
    }

    /// macOS drains again: shown as the drain in the same publish.
    @Test func resumingAboveTheLimitUnderAppleChargeLimitIsTheDrain() {
        #expect(end(paused) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
    }

    @Test func resumingBelowTheLimitIsChargingAsForAChargingPause() {
        #expect(end(paused, level: 75) == OverrideEnd(mode: .charging))
    }

    /// At the limit macOS holds: the hold, at once, with no drain left over.
    @Test func resumingAtTheLimitIsTheHold() {
        #expect(end(paused, level: 80) == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: false))
    }

    @Test func nothingIsPublishedAheadOffTheCharger() {
        #expect(end(paused, chargerConnected: false) == .plain)
    }

    @Test func resumingPutsThePausedOverrideBack() {
        let pausedRunOnBattery = UserTempChargingMode(limit: 95, isInhibit: true, pausesDischarge: true, resumesOverrideLimit: 0)
        #expect(end(pausedRunOnBattery) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .forceDischarge))
        #expect(end(pausedRunOnBattery, backend: .chte) == OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .forceDischarge))
    }

    @Test func aChargingPauseEndsAsItDid() {
        let charging = UserTempChargingMode(limit: 77, isInhibit: true)
        #expect(end(charging, level: 77) == OverrideEnd(mode: .charging))
    }

    @Test func theEndIsPublishedInOneGo() {
        let state = mode(.inhibit, override: paused)
        let ended = state.endingOverride(paused, with: OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
        #expect(ended.userTempOverride == nil)
        #expect(ended.systemIsDischargingToLimit)
        #expect(ended.stateDescription == L10n.AppChargingMode.State.Title.systemDischargingToLimit)
        #expect(BatteryIndicatorMode(appChargingMode: ended) == .discharging)

        let restored = state.endingOverride(paused, with: OverrideEnd(restoring: UserTempChargingMode(limit: 0), mode: .forceDischarge))
        #expect(restored.userTempOverride == UserTempChargingMode(limit: 0))
        #expect(restored.mode == .forceDischarge)
        #expect(BatteryIndicatorMode(appChargingMode: restored) == .discharging)
    }

    @Test func endingAPauseNoLongerInForceChangesNothing() {
        let state = mode(.inhibit, override: UserTempChargingMode(limit: 100))
        #expect(state.endingOverride(paused, with: OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true)) == state)
    }

    // MARK: - Holding the drain while powerd adopts the lowering

    @Test func anUnarmedHoldHoldsNothing() {
        let hold = DischargeResumeHold()
        #expect(!hold.holdsDrain(batteryLevel: 95, limitInForce: 80, overrideInForce: nil))
    }

    @Test func theDrainIsHeldWhileTheWindowIsOpen() {
        var hold = DischargeResumeHold()
        hold.arm()
        hold.record(suppressesAboveLimitStates: true, overrideInForce: nil, passIsStale: false)
        #expect(hold.holdsDrain(batteryLevel: 95, limitInForce: 80, overrideInForce: nil))
        #expect(!hold.holdsDrain(batteryLevel: 80, limitInForce: 80, overrideInForce: nil))
    }

    @Test func theHoldEndsWithTheWindow() {
        var hold = DischargeResumeHold()
        hold.arm()
        hold.record(suppressesAboveLimitStates: false, overrideInForce: nil, passIsStale: false)
        #expect(!hold.isArmed)
        #expect(!hold.holdsDrain(batteryLevel: 95, limitInForce: 80, overrideInForce: nil))
    }

    @Test func aNewOverrideEndsTheHold() {
        var hold = DischargeResumeHold()
        hold.arm()
        #expect(!hold.holdsDrain(batteryLevel: 95, limitInForce: 80, overrideInForce: paused))
        hold.record(suppressesAboveLimitStates: true, overrideInForce: paused, passIsStale: false)
        #expect(!hold.isArmed)
    }

    /// A pass begun under the pause and still applying its frozen limit says nothing about the
    /// lowering.
    @Test func aStalePassDoesNotEndTheHold() {
        var hold = DischargeResumeHold()
        hold.arm()
        hold.record(suppressesAboveLimitStates: false, overrideInForce: paused, passIsStale: true)
        #expect(hold.isArmed)
    }
}
