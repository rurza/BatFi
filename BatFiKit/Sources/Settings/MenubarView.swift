//
//  File.swift
//  
//
//  Created by Adam on 19/09/2023.
//

import Defaults
import L10n
import SettingsKit
import SwiftUI

struct MenubarView: View {
    @Default(.monochromeStatusIcon)                 private var monochrom
    @Default(.showBatteryPercentageInStatusIcon)    private var batteryPercentage
    @Default(.showChart)                            private var showChart
    @Default(.showPowerDiagram)                     private var showPowerDiagram
    @Default(.showHighEnergyImpactProcesses)        private var showHighEnergyImpactProcesses
    @Default(.highEnergyImpactProcessesThreshold)   private var highEnergyImpactProcessesThreshold
    @Default(.highEnergyImpactProcessesDuration)    private var highEnergyImpactProcessesDuration
    @Default(.highEnergyImpactProcessesCapacity)    private var highEnergyImpactProcessesCapacity


    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.menu) {
                Toggle(l10n.Button.Label.showBatteryChartInMenu, isOn: $showChart)
                Toggle(l10n.Button.Label.showPowerDiagram, isOn: $showPowerDiagram)
            }
            Section(title: l10n.Section.highEnergyImpactProcesses) {
                Toggle(l10n.Button.Label.highEnergyImpactProcessesShow, isOn: $showHighEnergyImpactProcesses)
                HStack {
                    Text(l10n.Label.highEnergyImpactProcessesThreshold)
                    Text(l10n.Label.highEnergyImpactProcessesThresholdUnit)
                    TextField("", value: $highEnergyImpactProcessesThreshold, format: .number)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 60)
                }
                HStack {
                    Text(l10n.Label.highEnergyImpactProcessesDuration)
                    TextField("", value: $highEnergyImpactProcessesDuration, format: .number)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 50)
                    Text(l10n.Label.highEnergyImpactProcessesDurationUnit)
                }
                HStack {
                    Text(l10n.Label.highEnergyImpactProcessesCapacity)
                    TextField("", value: $highEnergyImpactProcessesCapacity, format: .number)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 45)
                    Text(l10n.Label.highEnergyImpactProcessesCapacityUnit)
                }
            }
            Section(title: l10n.Section.statusIcon, bottomDivider: true) {
                Toggle(l10n.Button.Label.monochromeIcon, isOn: $monochrom)
                Toggle(l10n.Button.Label.batteryPercentage, isOn: $batteryPercentage)
            }
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Menubar"),
            title: L10n.Settings.Tab.Title.statusBar,
            toolbarIcon: NSImage(
                systemSymbolName: "menubar.rectangle",
                accessibilityDescription: L10n.Settings.Accessibility.Title.statusBar
            )!
        ) {
            Self()
        }

    }()
}
