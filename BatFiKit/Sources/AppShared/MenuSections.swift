//
//  MenuSections.swift
//  BatFi
//
//  Which of the optional sections the menu's top block shows, between the battery info and
//  the menu items. Each one comes with its own trailing separator, so hiding a section never
//  leaves a doubled separator or a gap behind.
//

import Foundation

public struct MenuSections: Equatable, Sendable {
    /// The power chart.
    public let chart: Bool
    /// "Power distribution".
    public let powerDistribution: Bool
    /// "Apps with high energy usage".
    public let highEnergyUsage: Bool
    /// The rule the automation override card names, or nil when the card is not shown.
    public let automationOverride: AutomationRule?

    /// - Parameter isUnlocked: a valid licence or a running trial. Without either the menu
    ///   keeps only the licence notice, the battery info and the menu items: the statistics
    ///   are part of what is locked, and no rule holds a limit while charging is back with
    ///   macOS, so the override card would not be true.
    public init(
        isUnlocked: Bool,
        showChart: Bool,
        showPowerDiagram: Bool,
        showHighEnergyImpactProcesses: Bool,
        manageCharging: Bool,
        automationEnabled: Bool,
        automationRules: [AutomationRule],
        automationActiveRuleID: String
    ) {
        chart = isUnlocked && showChart
        powerDistribution = isUnlocked && showPowerDiagram
        highEnergyUsage = isUnlocked && showHighEnergyImpactProcesses
        automationOverride = AutomationOverrideDisplay.overridingRule(
            isUnlocked: isUnlocked,
            manageCharging: manageCharging,
            automationEnabled: automationEnabled,
            rules: automationRules,
            activeRuleID: automationActiveRuleID
        )
    }
}
