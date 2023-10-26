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
    @Default(.temperatureSwitch)                          private var temperatureSwitch
    @Default(.disableSleep)                               private var disableAutomaticSleep
    @Default(.turnOnInhibitingChargingWhenGoingToSleep)   private var inhibitChargingOnSleep
    @Default(.showGreenLightMagSafeWhenInhibiting)        private var greenLight
    @Default(.downloadBetaVersion)                        private var checkForBetaUpdates
    @Default(.showDebugMenu)                              private var showDebugMenu
    @Default(.turnOnSystemChargeLimitingWhenGoingToSleep) private var enableSystemChargeLimitOnSleep

    // high energy
    @Default(.highEnergyImpactProcessesThreshold)         private var highEnergyImpactProcessesThreshold
    @Default(.highEnergyImpactProcessesDuration)          private var highEnergyImpactProcessesDuration
    @Default(.highEnergyImpactProcessesCapacity)          private var highEnergyImpactProcessesCapacity


    @Dependency(\.updater) private var updater


    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.charging, bottomDivider: true) {
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
                .disabled(enableSystemChargeLimitOnSleep)
                
                Toggle(isOn: $enableSystemChargeLimitOnSleep) {
                    Text(l10n.Button.Label.enableSystemChargeLimitOnSleep)
                }
                .disabled(inhibitChargingOnSleep)
                
                Toggle(isOn: $greenLight) {
                    Text(l10n.Button.Label.magsafeUseGreenLight)
                }
            }
            Section(bottomDivider: true, label: {
                Text(l10n.Section.highEnergyImpactProcesses)
                    .frame(maxWidth: 100)
                    .multilineTextAlignment(.trailing)
            }, content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.Label.highEnergyImpactProcessesThreshold) + Text(" \(highEnergyImpactProcessesThreshold)")
                    VStack(spacing: 0) {
                        Slider(value: .convert(from: $highEnergyImpactProcessesThreshold), in: 200...700, step: 100)
                        HStack {
                            Text("200")
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text("700")
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: 340)
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 2) {
                    let duration = Duration.seconds(highEnergyImpactProcessesDuration)
                    let style = Duration.UnitsFormatStyle(allowedUnits: [.minutes, .seconds], width: .abbreviated)
                    Text(l10n.Label.highEnergyImpactProcessesDuration) + Text(" \(duration.formatted(style))")
                    VStack(spacing: 0) {
                        Slider(value: $highEnergyImpactProcessesDuration, in: 30...300, step: 30)
                        HStack {
                            Text(l10n.Label.highEnergyImpactProcessesMinDuration)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text(l10n.Label.highEnergyImpactProcessesMaxDuration)
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: 340)
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.Label.highEnergyImpactProcessesCapacity) + Text(" \(highEnergyImpactProcessesCapacity)")
                    VStack(spacing: 0) {
                        Slider(value: .convert(from: $highEnergyImpactProcessesCapacity), in: 2...8, step: 1)
                        HStack {
                            Text("2")
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text("8")
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .frame(width: 340)
                }
            })
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
