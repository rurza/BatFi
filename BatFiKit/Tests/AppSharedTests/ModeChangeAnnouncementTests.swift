//
//  ModeChangeAnnouncementTests.swift
//  BatFi
//
//  MPX-43: the "New mode" banner fired every time macOS moved between its own sub-states of
//  the held mode — topping up, draining to the limit, holding — none of which the user did or
//  can stop. Those stay on the menu label and off Notification Center.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ModeChangeAnnouncementTests {
    private typealias Seen = ModeChangeAnnouncement.Seen

    private func inhibit(
        topUp: Bool = false,
        drain: Bool = false,
        hold: Bool = false,
        override: UserTempChargingMode? = nil,
        holdingFull: Bool = false
    ) -> AppChargingMode {
        AppChargingMode(
            mode: .inhibit,
            userTempOverride: override,
            chargerConnected: true,
            systemIsDischargingToLimit: drain,
            systemIsHoldingBelowLimit: hold,
            systemIsChargingPastLimit: topUp,
            isHoldingFullChargeUntilUnplugged: holdingFull
        )
    }

    private func seen(_ mode: AppChargingMode, limit: Int = 80, rule: String? = nil) -> Seen {
        Seen(mode: mode, limit: limit, automationRuleName: rule)
    }

    @Test func topUpToDrainIsQuiet() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(topUp: true)), to: seen(inhibit(drain: true))))
    }

    @Test func drainToTopUpIsQuiet() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(drain: true)), to: seen(inhibit(topUp: true))))
    }

    @Test func drainToPlainInhibitIsQuiet() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(drain: true)), to: seen(inhibit())))
    }

    @Test func plainInhibitToHoldIsQuiet() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit()), to: seen(inhibit(hold: true))))
    }

    @Test func theFirstModeSeenIsAnnounced() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: nil, to: seen(inhibit(topUp: true))) == false)
    }

    @Test func chargingIntoATopUpIsAnnounced() {
        let charging = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(charging), to: seen(inhibit(topUp: true))) == false)
    }

    @Test func leavingForChargingIsAnnounced() {
        let charging = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(drain: true)), to: seen(charging)) == false)
    }

    @Test func forceDischargeIsAnnounced() {
        let discharging = AppChargingMode(mode: .forceDischarge, userTempOverride: nil, chargerConnected: true)
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit()), to: seen(discharging)) == false)
    }

    @Test func aUserOverrideIsAnnounced() {
        let override = inhibit(override: UserTempChargingMode(limit: 100))
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(drain: true)), to: seen(override)) == false)
    }

    @Test func theChargeToFullHoldIsAnnounced() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit()), to: seen(inhibit(holdingFull: true))) == false)
    }

    /// The limit moving is something the user or an automation rule did, so a sub-state change
    /// that arrives with it is still news.
    @Test func aSubStateChangeWithANewLimitIsAnnounced() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(), limit: 90), to: seen(inhibit(drain: true), limit: 80)) == false)
    }

    @Test func aSubStateChangeWithANewAutomationRuleIsAnnounced() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(), rule: nil), to: seen(inhibit(drain: true), rule: "Work")) == false)
    }

    /// Not a sub-state change at all: left to the text dedupe, which lets a new limit through.
    @Test func theSameSubStateIsNotTreatedAsQuiet() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit(), limit: 90), to: seen(inhibit(), limit: 80)) == false)
    }

    // MARK: - Sailing

    private func sailing(_ resumeLevel: Int?, mode: ChargingMode = .inhibit) -> AppChargingMode {
        AppChargingMode(mode: mode, userTempOverride: nil, chargerConnected: true, sailingResumeLevel: resumeLevel)
    }

    /// Sailing posts no notification of its own: the hold being published over an inhibit that
    /// is already shown is a label change only.
    @Test func theSailingHoldAppearingOverAnInhibitIsQuiet() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(inhibit()), to: seen(sailing(70))))
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(sailing(70)), to: seen(inhibit())))
    }

    /// A rule's limit moves the resume level with it. Without sailing a limit change under an
    /// unchanged mode publishes nothing, so with it the new resume level is not news either.
    @Test func aNewResumeLevelIsQuietEvenWithANewLimit() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(sailing(70), limit: 80), to: seen(sailing(50), limit: 60)))
    }

    /// The edges of the cycle are mode changes, announced as BatFi starting or stopping a
    /// charge always has been.
    @Test func theEdgesOfTheSailingCycleAreAnnounced() {
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(sailing(nil, mode: .charging)), to: seen(sailing(70))) == false)
        #expect(ModeChangeAnnouncement.isQuietChange(from: seen(sailing(70)), to: seen(sailing(nil, mode: .charging))) == false)
    }
}
