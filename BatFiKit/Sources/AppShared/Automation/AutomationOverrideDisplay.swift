//
//  AutomationOverrideDisplay.swift
//  BatFi
//
//  Whether the UI may say that an automation rule is holding the charge limit right now. The
//  engine keeps evaluating rules whatever the licence, so the rule it publishes as active is
//  not on its own proof that anything is being held: while BatFi is locked, charging is handed
//  back to macOS and no limit is held at all.
//

import Foundation

public enum AutomationOverrideDisplay {
    /// The rule the override sentence names — in the menu and in the Charging pane alike — or
    /// nil when there is nothing true to say. A rule is only holding the limit while BatFi is
    /// unlocked, manages charging, has automation on, and the engine has a rule in force.
    public static func overridingRule(
        isUnlocked: Bool,
        manageCharging: Bool,
        automationEnabled: Bool,
        rules: [AutomationRule],
        activeRuleID: String
    ) -> AutomationRule? {
        guard manageCharging else { return nil }
        return activeRule(
            isUnlocked: isUnlocked,
            automationEnabled: automationEnabled,
            rules: rules,
            activeRuleID: activeRuleID
        )
    }

    /// The rule the Automation pane names as active, or nil. The pane's own terms — it does not
    /// ask about charge management — with the licence on top: a locked BatFi applies no rule.
    public static func activeRule(
        isUnlocked: Bool,
        automationEnabled: Bool,
        rules: [AutomationRule],
        activeRuleID: String
    ) -> AutomationRule? {
        guard isUnlocked, automationEnabled else { return nil }
        return AutomationEngine.activeRule(in: rules, activeRuleID: activeRuleID)
    }
}
