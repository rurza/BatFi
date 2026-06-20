//
//  AppChargingModeDescriptionTests.swift
//  BatFi
//
//  Unit tests for the charging-state description, focused on automation attribution:
//  the body must reflect the effective limit and name the active rule, while a manual
//  temp override always suppresses automation attribution (the override wins).
//

import Foundation
import Testing

@testable import AppShared

@Suite struct AppChargingModeDescriptionTests {
    private func mode(
        _ mode: ChargingMode,
        override: Int? = nil,
        chargerConnected: Bool = true
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: override.map(UserTempChargingMode.init(limit:)),
            chargerConnected: chargerConnected
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
