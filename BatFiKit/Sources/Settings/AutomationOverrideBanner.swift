//
//  AutomationOverrideBanner.swift
//  BatFi
//
//  Shown inside the Charging pane while an automation rule is actively overriding the
//  configured charge limit, so the slider value below isn't mistaken for the limit in effect.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import SwiftUI

struct AutomationOverrideBanner: View {
    @Default(.automationRules) private var rules
    @Default(.automationActiveRuleID) private var activeRuleID
    @Default(.automationEnabled) private var automationEnabled
    @Default(.manageCharging) private var manageCharging

    private var activeRule: AutomationRule? {
        rules.first { $0.id.uuidString == activeRuleID && $0.isEnabled }
    }

    var body: some View {
        // Only when automation can actually affect charging: management on, automation on,
        // and a rule currently matching.
        if manageCharging, automationEnabled, let activeRule {
            let name = activeRule.name.isEmpty ? L10n.Automation.untitledRule : activeRule.name
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.badge.a")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(L10n.Automation.overrideBannerActive(limit: activeRule.limit, name: name))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
            .padding(.bottom, 14)
        }
    }
}
