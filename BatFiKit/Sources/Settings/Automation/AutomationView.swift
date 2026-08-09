//
//  AutomationView.swift
//  BatFi
//
//  The Automation settings pane: a master toggle plus a reorderable, priority-ordered list
//  of charging-automation rules. Editing happens in a modal sheet.
//

import AppShared
import Cocoa
import Defaults
import DefaultsKeys
import L10n
import SettingsKit
import SharedUI
import SwiftUI

struct AutomationView: View {
    @Default(.automationEnabled) private var automationEnabled
    @Default(.automationRules) private var rules
    @Default(.automationActiveRuleID) private var activeRuleID

    @State private var editing: EditingContext?
    @State private var showHelp = false

    private struct EditingContext: Identifiable {
        let id: UUID
        var rule: AutomationRule
        var isNew: Bool
    }

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(bottomDivider: true) {
                EmptyView()
            } content: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Toggle(isOn: $automationEnabled) {
                            EmptyView()
                        }
                        .controlSize(.regular)
                        Text(L10n.Automation.enableToggle)
                    }
                    .toggleStyle(.switch)
                    .padding(.top, 10)

                    Text(L10n.Automation.enableDescription)
                        .settingDescription()

                    rulesList
                        .opacity(automationEnabled ? 1 : 0.4)
                        .disabled(!automationEnabled)

                    HStack {
                        Spacer()
                        Button {
                            addRule()
                        } label: {
                            Label(L10n.Automation.addRule, systemImage: "plus")
                        }
                        .disabled(!automationEnabled)
                    }

                    if let status = statusLine {
                        Text(status)
                            .settingDescription()
                    }

                    HStack {
                        Spacer()
                        Button {
                            showHelp.toggle()
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.Automation.helpButtonAccessibility)
                        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                            AutomationHelpView()
                        }
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $editing) { context in
            RuleEditorView(
                rule: context.rule,
                isNew: context.isNew,
                onSave: { save($0, isNew: context.isNew) },
                onDelete: context.isNew ? nil : { delete(context.rule) },
                onCancel: { editing = nil }
            )
        }
    }

    // MARK: - Rules list

    @ViewBuilder
    private var rulesList: some View {
        if rules.isEmpty {
            GroupBackground {
                Text(L10n.Automation.noRules)
                    .settingDescription()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            GroupBackground {
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                        if rule.id != rules.last?.id {
                            Divider().padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }

    private func ruleRow(_ rule: AutomationRule) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: enabledBinding(for: rule)) { EmptyView() }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? L10n.Automation.untitledRule : rule.name)
                    .fontWeight(.medium)
                Text(AutomationFormatting.summary(for: rule))
                    .settingDescription()
            }

            Spacer()

            if rule.id.uuidString == activeRuleID, automationEnabled, rule.isEnabled {
                Text(L10n.Automation.activeBadge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }

            Button {
                reorder(rule, by: -1)
            } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless)
                .disabled(rules.first?.id == rule.id)

            Button {
                reorder(rule, by: 1)
            } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .disabled(rules.last?.id == rule.id)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { edit(rule) }
    }

    // MARK: - Status line

    private var statusLine: String? {
        guard automationEnabled,
              let active = AutomationEngine.activeRule(in: rules, activeRuleID: activeRuleID) else {
            return nil
        }
        let name = active.name.isEmpty ? L10n.Automation.untitledRule : active.name
        return "“\(name)” — \(AutomationFormatting.summary(for: active))"
    }

    // MARK: - Mutations

    private func enabledBinding(for rule: AutomationRule) -> Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { newValue in
                guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                rules[index].isEnabled = newValue
            }
        )
    }

    private func addRule() {
        let new = AutomationRule(name: "", isEnabled: true, limit: 80)
        editing = EditingContext(id: new.id, rule: new, isNew: true)
    }

    private func edit(_ rule: AutomationRule) {
        editing = EditingContext(id: rule.id, rule: rule, isNew: false)
    }

    private func save(_ rule: AutomationRule, isNew: Bool) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        editing = nil
    }

    private func delete(_ rule: AutomationRule) {
        rules.removeAll { $0.id == rule.id }
        editing = nil
    }

    private func reorder(_ rule: AutomationRule, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        let target = index + offset
        guard target >= 0, target < rules.count else { return }
        rules.swapAt(index, target)
    }

    // MARK: - Pane

    static let pane: Pane<Self> = Pane(
        identifier: identifier,
        title: L10n.Automation.paneTitle,
        toolbarIcon: NSImage(
            systemSymbolName: "calendar.badge.clock",
            accessibilityDescription: L10n.Automation.paneAccessibilityTitle
        )!
    ) {
        Self()
    }

    static var identifier: NSToolbarItem.Identifier { .init("Automation") }
}
