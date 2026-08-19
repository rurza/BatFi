//
//  AppChargingModeDescriptionTests.swift
//  BatFi
//
//  Unit tests for the charging-state description, focused on automation attribution:
//  the body must reflect the effective limit and name the active rule, while a manual
//  temp override always suppresses automation attribution (the override wins).
//

import Foundation
import L10n
import Testing

@testable import AppShared

@Suite struct AppChargingModeDescriptionTests {
    private func mode(
        _ mode: ChargingMode,
        override: Int? = nil,
        chargerConnected: Bool = true,
        systemIsDischargingToLimit: Bool = false,
        systemIsHoldingBelowLimit: Bool = false
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: override.map(UserTempChargingMode.init(limit:)),
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: systemIsHoldingBelowLimit
        )
    }

    private func percent(_ fraction: Double) -> String {
        percentageFormatter.string(from: fraction as NSNumber)!
    }

    // MARK: - No automation (regression guard)

    @Test func chargingWithoutAutomationDoesNotMentionARule() {
        let description = mode(.charging).stateDescription(chargeLimitFraction: 0.8)
        #expect(description?.contains(percent(0.8)) == true)
        #expect(description?.contains("Work") == false)
    }

    @Test func inhibitWithoutAutomationDoesNotMentionARule() {
        let description = mode(.inhibit).stateDescription(chargeLimitFraction: 0.8)
        #expect(description?.contains(percent(0.8)) == true)
        #expect(description?.contains("Work") == false)
    }

    // MARK: - Automation attribution

    @Test func chargingWithAutomationShowsLimitAndRuleName() {
        let plain = mode(.charging).stateDescription(chargeLimitFraction: 0.85)
        let attributed = mode(.charging).stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        #expect(attributed?.contains(percent(0.85)) == true)
        #expect(attributed?.contains("Work") == true)
        #expect(attributed != plain)
    }

    @Test func inhibitWithAutomationShowsLimitAndRuleName() {
        let attributed = mode(.inhibit).stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        #expect(attributed?.contains(percent(0.85)) == true)
        #expect(attributed?.contains("Work") == true)
    }

    @Test func forceDischargeWithAutomationNamesTheRule() {
        let attributed = mode(.forceDischarge, chargerConnected: false)
            .stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        #expect(attributed?.contains("Work") == true)
    }

    // MARK: - Helper health outranks the mode

    // The mode is only ever as trustworthy as the helper that reported it. A record left
    // behind by a copy of BatFi that has since been deleted or moved reports `.enabled`
    // forever while every spawn fails, so the app can hold a mode it has no way to verify —
    // or, at launch, never get one at all and sit on `.initial`.

    @Test func degradedHelperIsReportedInsteadOfInitializing() {
        let description = mode(.initial).stateDescription(helperHealth: .degraded(.registeredButUnreachable))
        #expect(description != L10n.AppChargingMode.State.Title.initial)
        #expect(description == L10n.AppChargingMode.State.Title.helperNotRunning)
    }

    @Test func degradedHelperOutranksAStaleMode() {
        // Reporting "Inhibiting charging" while the helper is unreachable claims a pause
        // that nothing is holding.
        for staleMode in [ChargingMode.charging, .inhibit, .forceDischarge] {
            let description = mode(staleMode).stateDescription(helperHealth: .degraded(.notRegistered))
            #expect(description == L10n.AppChargingMode.State.Title.helperNotRunning)
        }
    }

    @Test func unknownHelperHealthStillReportsInitializing() {
        // The launch window, before the first probe lands, really is initializing.
        let description = mode(.initial).stateDescription(helperHealth: .unknown)
        #expect(description == L10n.AppChargingMode.State.Title.initial)
    }

    @Test func healthyHelperReportsTheModeUnchanged() {
        for anyMode in [ChargingMode.initial, .charging, .inhibit, .forceDischarge] {
            let withHealth = mode(anyMode).stateDescription(helperHealth: .healthy)
            #expect(withHealth == mode(anyMode).stateDescription)
        }
    }

    // MARK: - The system draining to the limit is not BatFi pausing

    // On firmware whose mechanism owns the charging decision, macOS drains the battery down
    // to the limit by itself. BatFi writes no inhibit there and takes `.inhibit` as the
    // honest mode for "charge is being held, just not by me" — but the title said
    // "Inhibiting charging" while the battery visibly fell, which is the one reading a user
    // watching 61% drop toward a 55% limit can prove wrong.

    @Test func systemDischargingToTheLimitIsNotReportedAsInhibiting() {
        let title = mode(.inhibit, systemIsDischargingToLimit: true).stateDescription
        #expect(title != L10n.AppChargingMode.State.Title.inhibit)
        #expect(title == L10n.AppChargingMode.State.Title.systemDischargingToLimit)
    }

    @Test func inhibitingWithoutASystemDrainIsUnchanged() {
        let title = mode(.inhibit).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.inhibit)
    }

    /// The flag describes why charge is being held; it says nothing about any other mode and
    /// must not leak into one.
    @Test func aSystemDrainDoesNotRelabelTheOtherModes() {
        for otherMode in [ChargingMode.charging, .forceDischarge] {
            let drained = mode(otherMode, systemIsDischargingToLimit: true).stateDescription
            #expect(drained == mode(otherMode).stateDescription)
        }
    }

    // MARK: - Charge held below the limit

    // Measured on 26A5416b, 2026-08-19: 56% against a 60% limit, 0 mA, `CHNC` bit 24 set, for
    // two hours. The mode decision reads `batteryLevel < limitInForce` and so chose
    // `.charging` — the menu said "Charging to the limit" while no current flowed at all.
    // `.inhibit` is the honest mode, and "Inhibiting charging" is still the wrong sentence
    // for it: BatFi wrote nothing, and the number the user set is not the one being held at.

    @Test func systemHoldingChargeBelowTheLimitIsNotReportedAsInhibiting() {
        let title = mode(.inhibit, systemIsHoldingBelowLimit: true).stateDescription
        #expect(title != L10n.AppChargingMode.State.Title.inhibit)
        #expect(title == L10n.AppChargingMode.State.Title.systemHoldingBelowLimit)
    }

    @Test func inhibitingWithoutASystemHoldIsUnchanged() {
        let title = mode(.inhibit).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.inhibit)
    }

    /// Same containment the drain flag gets: it explains why charge is being held and must
    /// not leak into a mode where nothing is.
    @Test func aSystemHoldDoesNotRelabelTheOtherModes() {
        for otherMode in [ChargingMode.charging, .forceDischarge] {
            let held = mode(otherMode, systemIsHoldingBelowLimit: true).stateDescription
            #expect(held == mode(otherMode).stateDescription)
        }
    }

    @Test func aTempOverrideOutranksASystemHold() {
        let title = mode(.inhibit, override: 100, systemIsHoldingBelowLimit: true).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.chargeOverride)
    }

    /// The two cannot both be true of one reading — a drain needs the battery above the limit
    /// and a hold needs it below — but the struct cannot express that, so the precedence is
    /// pinned here. The drain wins: it is the one the user can watch happening.
    @Test func aDrainOutranksAHoldIfBothAreSomehowSet() {
        let title = mode(
            .inhibit,
            systemIsDischargingToLimit: true,
            systemIsHoldingBelowLimit: true
        ).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.systemDischargingToLimit)
    }

    /// A temp override is BatFi acting on the user's own instruction, and the override text
    /// already says so. It outranks the system's drain for the same reason it outranks
    /// automation attribution below.
    @Test func aTempOverrideOutranksASystemDrain() {
        let title = mode(.inhibit, override: 100, systemIsDischargingToLimit: true).stateDescription
        #expect(title == L10n.AppChargingMode.State.Title.chargeOverride)
    }

    // MARK: - Temp override wins over automation

    @Test func tempOverrideSuppressesAutomationAttribution() {
        let withName = mode(.charging, override: 100)
            .stateDescription(chargeLimitFraction: 0.85, automationRuleName: "Work")
        let withoutName = mode(.charging, override: 100)
            .stateDescription(chargeLimitFraction: 0.85)
        // Override text is identical with or without an active automation rule, and never
        // attributes the charge to automation.
        #expect(withName == withoutName)
        #expect(withName?.contains("Work") == false)
    }
}
