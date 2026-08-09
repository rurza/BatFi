//
//  AutomationOverrideBanner.swift
//  BatFi
//
//  What BatFi says while an automation rule is actively overriding the configured charge
//  limit. Shown in the Charging pane, where the slider below would otherwise be mistaken
//  for the limit in effect, and in the menu, which is asked the same question — what is
//  BatFi doing right now — by someone who cannot see the slider at all. One sentence,
//  written once, so the two cannot answer it differently.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import SharedUI
import SwiftUI

/// The sentence and its card, given the rule that is winning. Wraps to as many lines as the
/// width it is handed needs: the pane gives it a settings column, the menu gives it 220pt.
public struct AutomationOverrideCard: View {
    private let rule: AutomationRule

    public init(rule: AutomationRule) {
        self.rule = rule
    }

    public var body: some View {
        let name = rule.name.isEmpty ? L10n.Automation.untitledRule : rule.name
        HStack(alignment: .top, spacing: 8) {
            // BatFi's own green, not `.accentColor`. The card is the app saying something
            // about itself, and `.accentColor` here would be whatever the user picked in
            // System Settings — blue, by default, on a Mac that has never been touched.
            Image(systemName: "bolt.badge.a")
                .foregroundStyle(Color.appAccent)
                .accessibilityHidden(true)
            Text(L10n.Automation.overrideBannerActive(limit: rule.limit, name: name))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.appAccent.opacity(0.12))
        }
    }
}

/// The Charging pane's use of it: present only when automation can actually affect charging —
/// management on, automation on, and a rule currently matching.
struct AutomationOverrideBanner: View {
    @Default(.automationRules) private var rules
    @Default(.automationActiveRuleID) private var activeRuleID
    @Default(.automationEnabled) private var automationEnabled
    @Default(.manageCharging) private var manageCharging

    var body: some View {
        if manageCharging, automationEnabled,
           let activeRule = AutomationEngine.activeRule(in: rules, activeRuleID: activeRuleID) {
            AutomationOverrideCard(rule: activeRule)
                .padding(.bottom, 14)
        }
    }
}
