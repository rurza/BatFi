//
//  MenubarView.swift
//
//
//  Created by Adam on 19/09/2023.
//

import Defaults
import L10n
import SettingsKit
import SwiftUI

struct MenubarView: View {
    @Default(.showChart) private var showChart
    @Default(.showPowerDiagram) private var showPowerDiagram
    @Default(.showHighEnergyImpactProcesses) private var showHighEnergyImpactProcesses
    @Default(.showBatteryCycleCount) private var showBatteryCycleCount
    @Default(.showBatteryHealth) private var showBatteryHealth
    @Default(.showBatteryTemperature) private var showBatteryTemperature
    @Default(.showPowerSource) private var showPowerSource
    @Default(.showLastDischarge) private var showLastDischarge
    @Default(.showLastFullCharge) private var showLastFullCharge
    @Default(.showPowerModeOptions) private var showPowerModeOptions
    @State private var showingPopover = false

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.menu, bottomDivider: true) {
                Toggle(l10n.Button.Label.showPowerSource, isOn: $showPowerSource)
                Toggle(l10n.Button.Label.showBatteryCycles, isOn: $showBatteryCycleCount)
                Toggle(l10n.Button.Label.showBatteryTemperature, isOn: $showBatteryTemperature)
                Toggle(l10n.Button.Label.showBatteryHealth, isOn: $showBatteryHealth)
                Toggle(l10n.Button.Label.showLastDischargeDate, isOn: $showLastDischarge)
                Toggle(l10n.Button.Label.showLastFullChargeDate, isOn: $showLastFullCharge)
                Text("").accessibilityHidden(true) // used to separate content visually
                Toggle(l10n.Button.Label.showBatteryChartInMenu, isOn: $showChart)
                Toggle(l10n.Button.Label.showPowerDiagram, isOn: $showPowerDiagram)
                Toggle(l10n.Button.Label.showPowerModeOptions, isOn: $showPowerModeOptions)
                HStack(alignment: .top) {
                    Toggle(l10n.Button.Label.showHighEnergyImpactProcesses, isOn: $showHighEnergyImpactProcesses)
                    Button(action: { showingPopover.toggle() }, label: { Text(L10n.Menu.Label.settings) })
                        .popover(isPresented: $showingPopover, content: {
                            HighEnergyImpactSettingsView()
                        })
                }
            }
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("Menu"),
        title: L10n.Settings.Tab.Title.menu,
        toolbarIcon: NSImage(
            systemSymbolName: "filemenu.and.cursorarrow",
            accessibilityDescription: L10n.Settings.Accessibility.Title.menu
        )!
    ) {
        Self()
    }
}
