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
import Settings
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

    private var secondaryText: String? {
        if let active = activeRule {
            let detail = activeDetail(active)
            return detail.isEmpty ? nil : detail
        }
        if let next = AutomationEngine.nextScheduled(in: rules, enabled: true, after: Date()) {
            let name = next.rule.name.isEmpty ? L10n.Automation.untitledRule : next.rule.name
            return L10n.Automation.menuNext(name: name, when: Self.relativeDateTime(next.start))
        }
        return nil
    }

    private func activeDetail(_ rule: AutomationRule) -> String {
        var parts: [String] = []
        switch rule.schedule {
        case let .recurring(_, time):
            parts.append(L10n.Automation.menuActiveUntil(AutomationFormatting.time(time.end)))
        case let .oneOff(_, time):
            parts.append(L10n.Automation.menuActiveUntil(AutomationFormatting.time(time.end)))
        case nil:
            break
        }
        if rule.location != nil {
            parts.append(AutomationFormatting.locationSummary(rule.location))
        }
        return parts.joined(separator: " · ")
    }

    private static func relativeDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
