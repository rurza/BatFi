//
//  InhibitPauseTests.swift
//  BatFi
//
//  What the user is told about "Inhibit Charging": a pause, from the click. Under Apple's
//  charge limit the pause is a frozen limit that powerd takes up to a minute to adopt, and
//  the battery may charge on meanwhile; the menu used to say "Pausing charging…" until powerd
//  confirmed it. The owner wants the state asked for shown at once and held through that
//  window, so an armed inhibit is a pause whatever the mode underneath.
//

import Foundation
import L10n
import Shared
import Testing

@testable import AppShared

@Suite struct InhibitPauseTests {
    private func mode(
        _ mode: ChargingMode,
        inhibitAt limit: Int? = 77,
        chargerConnected: Bool = true
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: limit.map { UserTempChargingMode(limit: $0, isInhibit: true) },
            chargerConnected: chargerConnected
        )
    }

    private func plainOverride(_ mode: ChargingMode, limit: Int) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: UserTempChargingMode(limit: limit),
            chargerConnected: true
        )
    }

    private func percent(_ limit: Int) -> String {
        percentageFormatter.string(from: Double(limit) / 100 as NSNumber)!
    }

    // MARK: - Paused

    /// Whatever the mode: `.charging` until the pass after the click, or while a paused
    /// battery a point below the frozen limit is charged back; `.forceDischarge` on the
    /// inhibit backends bringing a battery that crept up back to the level.
    @Test func anArmedInhibitIsPausedAtItsLevel() {
        for state in [ChargingMode.charging, .inhibit, .forceDischarge] {
            #expect(ManualInhibit.pausedLimit(of: mode(state)) == 77)
        }
    }

    @Test func aPlainOverrideIsNotAPause() {
        #expect(ManualInhibit.pausedLimit(of: plainOverride(.inhibit, limit: 77)) == nil)
    }

    @Test func noOverrideIsNotAPause() {
        #expect(ManualInhibit.pausedLimit(of: mode(.inhibit, inhibitAt: nil)) == nil)
    }

    @Test func anUnpluggedInhibitIsNotAPause() {
        #expect(ManualInhibit.pausedLimit(of: mode(.inhibit, chargerConnected: false)) == nil)
    }

    @Test func replacingTheOverrideCarriesEverythingElse() {
        let state = AppChargingMode(
            mode: .inhibit,
            userTempOverride: nil,
            chargerConnected: true,
            systemIsDischargingToLimit: true,
            systemIsHoldingBelowLimit: true,
            systemIsChargingPastLimit: true,
            isHoldingFullChargeUntilUnplugged: true,
            isAwaitingModeForChargerChange: true
        )
        let next = state.replacingOverride(UserTempChargingMode(limit: 100))
        #expect(next.userTempOverride == UserTempChargingMode(limit: 100))
        #expect(next.mode == .inhibit)
        #expect(next.chargerConnected)
        #expect(next.systemIsDischargingToLimit)
        #expect(next.systemIsHoldingBelowLimit)
        #expect(next.systemIsChargingPastLimit)
        #expect(next.isHoldingFullChargeUntilUnplugged)
        #expect(next.isAwaitingModeForChargerChange)
    }

    // MARK: - Title

    @Test func anArmedInhibitIsTitledChargingPausedAtItsLevel() {
        #expect(mode(.charging).stateDescription == L10n.AppChargingMode.State.Title.chargingPausedAt(percent(77)))
        #expect(mode(.inhibit).stateDescription == L10n.AppChargingMode.State.Title.chargingPausedAt(percent(77)))
    }

    /// Charge to 100%, Run on Battery and Shortcuts limits keep their wording exactly.
    @Test func aPlainOverrideKeepsTheOverrideTitle() {
        #expect(plainOverride(.inhibit, limit: 77).stateDescription == L10n.AppChargingMode.State.Title.chargeOverride)
    }

    // MARK: - Description

    @Test func anArmedInhibitSaysHowToResume() {
        #expect(mode(.charging).stateDescription(chargeLimitFraction: 0.8) == L10n.AppChargingMode.State.Description.chargingPaused)
    }

    @Test func aPlainOverrideKeepsTheTemporaryLimitDescription() {
        #expect(
            plainOverride(.inhibit, limit: 77).stateDescription(chargeLimitFraction: 0.8)
                == L10n.AppChargingMode.State.Description.tempChargingTo(percent(77))
        )
    }

    // MARK: - Notification

    /// Announced at once, as the pause, whatever the mode underneath.
    @Test func anArmedInhibitIsAnnounced() {
        #expect(ModeChangeAnnouncement.consideration(of: mode(.charging), manageCharging: true) == .announce)
        #expect(ModeChangeAnnouncement.consideration(of: mode(.inhibit), manageCharging: true) == .announce)
    }

    @Test func aPlainOverrideIsStillAnnouncedWhileCharging() {
        #expect(
            ModeChangeAnnouncement.consideration(of: plainOverride(.charging, limit: 100), manageCharging: true)
                == .announce
        )
    }

    // MARK: - Icon

    @Test func anArmedInhibitDrawsThePlugWhateverTheMode() {
        for state in [ChargingMode.charging, .inhibit, .forceDischarge] {
            #expect(BatteryIndicatorMode(appChargingMode: mode(state)) == .inhibited)
        }
    }

    // MARK: - Menu

    @Test func anInhibitIsEndedWithResumeCharging() {
        #expect(
            StatusMenuCommands.stopOverrideTitle(for: UserTempChargingMode(limit: 77, isInhibit: true))
                == L10n.Menu.Label.resumeCharging
        )
    }

    @Test func aPlainOverrideIsEndedWithStopOverride() {
        #expect(
            StatusMenuCommands.stopOverrideTitle(for: UserTempChargingMode(limit: 77))
                == L10n.Menu.Label.stopOverride
        )
    }

    /// While the frozen limit is applied the mode can still be `.charging`, which is where
    /// the command is offered; a second click would only re-arm the same pause.
    @Test func inhibitChargingIsNotOfferedWhileAnInhibitIsArmed() {
        #expect(!StatusMenuCommands.showsInhibitCharging(mode: mode(.charging), backend: .systemChargeLimit))
    }

    @Test func inhibitChargingIsStillOfferedOverAPlainOverride() {
        #expect(StatusMenuCommands.showsInhibitCharging(mode: plainOverride(.charging, limit: 100), backend: .systemChargeLimit))
    }
}
