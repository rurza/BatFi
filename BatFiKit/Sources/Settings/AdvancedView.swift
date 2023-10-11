//
//  File.swift
//  
//
//  Created by Adam on 21/09/2023.
//

import AppShared
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import SettingsKit
import SwiftUI

struct AdvancedView: View {
    @Default(.temperatureSwitch)                        private var temperatureSwitch
    @Default(.disableSleep)                             private var disableAutomaticSleep
    @Default(.turnOnInhibitingChargingWhenGoingToSleep) private var inhibitChargingOnSleep
    @Default(.showGreenLightMagSafeWhenInhibiting)      private var greenLight
    @Default(.downloadBetaVersion)                      private var checkForBetaUpdates
    @Default(.showDebugMenu)                            private var showDebugMenu
    @Default(.highEnergyImpactProcessesThreshold)       private var highEnergyImpactProcessesThreshold
    @Default(.highEnergyImpactProcessesDuration)        private var highEnergyImpactProcessesDuration
    @Default(.highEnergyImpactProcessesCapacity)        private var highEnergyImpactProcessesCapacity


    @Dependency(\.updater) private var updater


    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.charging) {
                Toggle(isOn: $temperatureSwitch) {
                    Text(l10n.Button.Label.turnOffChargingWhenBatteryIsHot)
                        .help(l10n.Button.Tooltip.turnOffChargingWhenBatteryIsHot)
                }
                
                Toggle(isOn: $disableAutomaticSleep) {
                    Text(l10n.Button.Label.disableAutomaticSleep)
                        .help(l10n.Button.Tooltip.disableAutomaticSleep)
                }
                
                Toggle(isOn: $inhibitChargingOnSleep) {
                    Text(l10n.Button.Label.pauseChargingOnSleep)
                }
                
                Toggle(isOn: $greenLight) {
                    Text(l10n.Button.Label.magsafeUseGreenLight)
                }
            }
            Section(title: l10n.Section.processes, bottomDivider: true) {
                HStack {
                    Text(l10n.Field.Label.highEnergyImpactProcessesThreshold)
                    Text(l10n.Field.Label.highEnergyImpactProcessesThresholdUnit)
                    TextField("", value: $highEnergyImpactProcessesThreshold, format: .number)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 60)
                }
                HStack {
                    Text(l10n.Field.Label.highEnergyImpactProcessesDuration)
                    TextField("", value: $highEnergyImpactProcessesDuration, format: .number)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 50)
                    Text(l10n.Field.Label.highEnergyImpactProcessesDurationUnit)
                }
                HStack {
                    Text(l10n.Field.Label.highEnergyImpactProcessesCapacity)
                    TextField("", value: $highEnergyImpactProcessesCapacity, format: .number)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 45)
                    Text(l10n.Field.Label.highEnergyImpactProcessesCapacityUnit)
                }
            }
            Section(title: l10n.Section.updates) {
                Toggle(l10n.Button.Label.checkForBetaUpdates, isOn: $checkForBetaUpdates)
                    .onChange(of: checkForBetaUpdates) { checkForBetaUpdates in
                        if checkForBetaUpdates {
                            updater.checkForUpdates()
                        }
                    }
            }
            Section(title: l10n.Section.debug) {
                Toggle(l10n.Button.Label.debugMenu, isOn: $showDebugMenu)
            }
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Advanved"),
            title: L10n.Settings.Tab.Title.advanced,
            toolbarIcon: NSImage(
                systemSymbolName: "gearshape.2",
                accessibilityDescription: L10n.Settings.Accessibility.Title.advanced
            )!
        ) {
            Self()
        }
    }()
}
