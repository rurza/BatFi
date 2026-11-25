//
//  MenuSectionsTests.swift
//  BatFi
//
//  What the menu's top block shows, and when the UI may say an automation rule is holding
//  the limit. Locked — no licence and no running trial — the statistics and the override card
//  go, whatever the settings say: the statistics are locked, and no limit is held at all.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct MenuSectionsTests {
    private let rule = AutomationRule(name: "Office", isEnabled: true, limit: 70)

    private func sections(
        isUnlocked: Bool,
        showChart: Bool = true,
        showPowerDiagram: Bool = true,
        showHighEnergyImpactProcesses: Bool = true,
        manageCharging: Bool = true,
        automationEnabled: Bool = true,
        activeRuleID: String? = nil
    ) -> MenuSections {
        MenuSections(
            isUnlocked: isUnlocked,
            showChart: showChart,
            showPowerDiagram: showPowerDiagram,
            showHighEnergyImpactProcesses: showHighEnergyImpactProcesses,
            manageCharging: manageCharging,
            automationEnabled: automationEnabled,
            automationRules: [rule],
            automationActiveRuleID: activeRuleID ?? rule.id.uuidString
        )
    }

    // MARK: - Locked

    @Test func lockedHidesEverySectionEvenWithEverySettingOn() {
        let locked = sections(isUnlocked: false)
        #expect(!locked.chart)
        #expect(!locked.powerDistribution)
        #expect(!locked.highEnergyUsage)
        #expect(locked.automationOverride == nil)
    }

    // MARK: - Unlocked

    @Test func unlockedShowsEverySectionTheSettingsAskFor() {
        let unlocked = sections(isUnlocked: true)
        #expect(unlocked.chart)
        #expect(unlocked.powerDistribution)
        #expect(unlocked.highEnergyUsage)
        #expect(unlocked.automationOverride == rule)
    }

    @Test(arguments: [
        (true, false, false),
        (false, true, false),
        (false, false, true),
        (false, false, false),
    ])
    func unlockedFollowsEachShowSetting(chart: Bool, power: Bool, highEnergy: Bool) {
        let unlocked = sections(
            isUnlocked: true,
            showChart: chart,
            showPowerDiagram: power,
            showHighEnergyImpactProcesses: highEnergy
        )
        #expect(unlocked.chart == chart)
        #expect(unlocked.powerDistribution == power)
        #expect(unlocked.highEnergyUsage == highEnergy)
    }

    // MARK: - Automation override card

    @Test func overrideCardNeedsChargeManagement() {
        #expect(sections(isUnlocked: true, manageCharging: false).automationOverride == nil)
    }

    @Test func overrideCardNeedsAutomationOn() {
        #expect(sections(isUnlocked: true, automationEnabled: false).automationOverride == nil)
    }

    @Test func overrideCardNeedsARuleInForce() {
        #expect(sections(isUnlocked: true, activeRuleID: "").automationOverride == nil)
        #expect(sections(isUnlocked: true, activeRuleID: UUID().uuidString).automationOverride == nil)
    }

    @Test func overrideCardIgnoresADisabledRule() {
        var disabled = rule
        disabled.isEnabled = false
        let unlocked = MenuSections(
            isUnlocked: true,
            showChart: false,
            showPowerDiagram: false,
            showHighEnergyImpactProcesses: false,
            manageCharging: true,
            automationEnabled: true,
            automationRules: [disabled],
            automationActiveRuleID: disabled.id.uuidString
        )
        #expect(unlocked.automationOverride == nil)
    }

    @Test func overrideCardIsIndependentOfTheShowSettings() {
        let unlocked = sections(
            isUnlocked: true,
            showChart: false,
            showPowerDiagram: false,
            showHighEnergyImpactProcesses: false
        )
        #expect(unlocked.automationOverride == rule)
    }
}

@Suite struct AutomationOverrideDisplayTests {
    private let rule = AutomationRule(name: "Home", isEnabled: true, limit: 60)

    @Test func chargingPaneSentenceIsHiddenWhileLocked() {
        let named = AutomationOverrideDisplay.overridingRule(
            isUnlocked: false,
            manageCharging: true,
            automationEnabled: true,
            rules: [rule],
            activeRuleID: rule.id.uuidString
        )
        #expect(named == nil)
    }

    @Test func chargingPaneSentenceNamesTheRuleWhileUnlocked() {
        let named = AutomationOverrideDisplay.overridingRule(
            isUnlocked: true,
            manageCharging: true,
            automationEnabled: true,
            rules: [rule],
            activeRuleID: rule.id.uuidString
        )
        #expect(named == rule)
    }

    @Test func automationPaneStatusIsHiddenWhileLocked() {
        let named = AutomationOverrideDisplay.activeRule(
            isUnlocked: false,
            automationEnabled: true,
            rules: [rule],
            activeRuleID: rule.id.uuidString
        )
        #expect(named == nil)
    }

    @Test func automationPaneStatusKeepsItsOwnTermsWhileUnlocked() {
        // It never asked about charge management, and still does not.
        let named = AutomationOverrideDisplay.activeRule(
            isUnlocked: true,
            automationEnabled: true,
            rules: [rule],
            activeRuleID: rule.id.uuidString
        )
        #expect(named == rule)
        let off = AutomationOverrideDisplay.activeRule(
            isUnlocked: true,
            automationEnabled: false,
            rules: [rule],
            activeRuleID: rule.id.uuidString
        )
        #expect(off == nil)
    }
}
