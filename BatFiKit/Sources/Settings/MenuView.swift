import Defaults
import L10n
import SettingsKit
import SwiftUI

struct MenuView: View {
    @Default(.showHighEnergyImpactProcesses)      private var showHighEnergyImpactProcesses
    @Default(.highEnergyImpactProcessesThreshold) private var highEnergyImpactProcessesThreshold
    @Default(.highEnergyImpactProcessesDuration)  private var highEnergyImpactProcessesDuration
    @Default(.highEnergyImpactProcessesCapacity)  private var highEnergyImpactProcessesCapacity
    
    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
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
        }
    }
    
    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Menu"),
            title: L10n.Settings.Tab.Title.menu,
            toolbarIcon: NSImage(
                systemSymbolName: "line.3.horizontal.circle.fill",
                accessibilityDescription: L10n.Settings.Accessibility.Title.menu
            )!
        ) {
            Self()
        }
    }()
}
