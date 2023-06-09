//
//  ChargingView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import SettingsKit
import SwiftUI

struct ChargingView: View {
    @Default(.chargeLimit)                  private var chargeLimit
    @Default(.manageCharging)               private var manageCharging
    @Default(.temperatureSwitch)            private var temperatureSwitch
    @Default(.allowDischargingFullBattery)  private var dischargeBatteryWhenFull
    @Default(.disableSleep)                 private var disableSleep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Container(contentWidth: settingsContentWidth) {
                Section(bottomDivider: true) {
                    EmptyView()
                } content: {
                    let l10n = L10n.Settings.self
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Toggle(isOn: $manageCharging) {
                                EmptyView()
                            }
                            .toggleStyle(.switch)
                            Text(l10n.Button.Label.automaticallyManageCharging)
                        }
                        .padding(.bottom, 30)
                        .padding(.top, 10)

                        VStack(alignment: .leading, spacing: 2) {
                            let label = l10n.Slider.Label.turnOffChargingAt(
                                percentageFormatter.string(from: NSNumber(value: Double(chargeLimit) / 100))!
                            )
                            Text(label)
                                .foregroundColor(manageCharging ? .primary : .secondary)
                            Slider(value: .convert(from: $chargeLimit), in: 60...90, step: 5) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("60%")
                            } maximumValueLabel: {
                                Text("90%")
                            }
                            .disabled(!manageCharging)
                        }
                    }
                    .padding(.bottom, 10)
                    Toggle(isOn: $temperatureSwitch) {
                        Text(l10n.Button.Label.turnOffChargingWhenBatteryIsHot)
                            .help(l10n.Button.Tooltip.turnOffChargingWhenBatteryIsHot)
                    }
                    .disabled(!manageCharging)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: $dischargeBatteryWhenFull) {
                            Text(l10n.Button.Label.dischargeBatterWhenOvercharged)
                                .withBetaLabel()
                                .help(l10n.Button.Tooltip.dischargeBatterWhenOvercharged)
                        }
                        .disabled(!manageCharging)
                        Text(l10n.Button.Description.lidMustBeOpened)
                            .settingDescription()
                    }
                    Toggle(isOn: $disableSleep) {
                        Text(l10n.Button.Label.disableSleep)
                            .withBetaLabel()
                            .help(l10n.Button.Tooltip.disableSleep)
                    }
                    .disabled(!manageCharging)
                }
                Section {
                    EmptyView()
                } content: {
                    VStack(alignment: .leading, spacing: 0) {
                        let l10n = L10n.Settings.Label.self
                        Group {
                            Text(l10n.chargingRecommendationPart1)
                            Text(l10n.chargingRecommendationPart2)
                        }
                        .settingDescription()
                    }
                }
            }
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Charging"),
            title: L10n.Settings.Tab.Title.charging,
            toolbarIcon: NSImage(
                systemSymbolName: "bolt.batteryblock.fill",
                accessibilityDescription: L10n.Settings.Accessibility.Title.charging
            )!
        ) {
            Self()
        }
    }()
}

struct ChargingView_Previews: PreviewProvider {
    static var previews: some View {
        ChargingView()
    }
}
