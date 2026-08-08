//
//  AutomationMenuInfoView.swift
//  BatFi
//
//  The automation status as a section inside the width-limited MenuContent. Wraps within
//  the fixed menu width instead of stretching it (a native menu item would size to its
//  title). Mirrors the header + content layout of the other menu sections.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import SwiftUI

struct AutomationMenuInfoView: View {
    @Default(.automationRules) private var rules
    @Default(.automationActiveRuleID) private var activeRuleID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Automation.paneTitle)
                .foregroundColor(.secondary)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            GroupBox {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let secondaryText {
                        Text(secondaryText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(6)
            }
        }
        .font(.callout)
    }

    private var activeRule: AutomationRule? {
        rules.first { $0.id.uuidString == activeRuleID && $0.isEnabled }
    }

    private var primaryText: String {
        if let active = activeRule {
            let name = active.name.isEmpty ? L10n.Automation.untitledRule : active.name
            return L10n.Automation.menuActive(limit: active.limit, name: name)
        }
        return L10n.Automation.menuIdle
    }

    /// Nothing under the active rule. Its name and its limit are the whole message: the
    /// card answers "what is BatFi doing", and the conditions that got the rule here —
    /// the hours it runs, the area it watches — are the rule's definition, which belongs
    /// in the editor that owns it rather than restated in a menu every time it fires.
    ///
    /// The idle case still says what is coming, because there the card has no rule to name
    /// and "Idle" alone answers nothing.
    private var secondaryText: String? {
        guard activeRule == nil else { return nil }
        if let next = AutomationEngine.nextScheduled(in: rules, enabled: true, after: Date()) {
            let name = next.rule.name.isEmpty ? L10n.Automation.untitledRule : next.rule.name
            return L10n.Automation.menuNext(name: name, when: Self.relativeDateTime(next.start))
        }
        return nil
    }

    private static func relativeDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
