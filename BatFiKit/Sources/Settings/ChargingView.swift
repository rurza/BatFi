//
//  ChargingView.swift
//
//
//  Created by Adam on 05/05/2023.
//

import AppShared
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import SettingsKit
import SharedUI
import SwiftUI

struct ChargingView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.manageCharging) private var manageCharging
    @Default(.allowDischargingFullBattery) private var dischargeBatteryWhenFull
    @Default(.turnOnInhibitingChargingWhenGoingToSleep) private var inhibitChargingOnSleep
    @Default(.disableSleepDuringDischarging) private var disableSleepDuringDischarging

    @Dependency(\.systemVersionClient) var systemVersion

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
                            .controlSize(.regular)
                            Text(l10n.Button.Label.automaticallyManageCharging)
                        }
                        .toggleStyle(.switch)
                        .padding(.bottom, 20)
                        .padding(.top, 10)

                        GroupBackground {
                            VStack(alignment: .leading, spacing: 6) {
                                AutomationOverrideBanner()
                                VStack(alignment: .leading, spacing: 14) {
                                    let label = l10n.Slider.Label.turnOffChargingAt(
                                        percentageFormatter.string(from: NSNumber(value: Double(chargeLimit) / 100))!
                                    )
                                    Text(label)
                                        .foregroundColor(manageCharging ? .primary : .secondary)
                                    HStack {
                                        Slider(value: .convert(from: $chargeLimit), in: 50 ... 90, step: 5) {
                                            EmptyView()
                                        } minimumValueLabel: {
                                            Text(L10n.Settings.Label.lowestLimit)
                                        } maximumValueLabel: {
                                            Text(L10n.Settings.Label.highestLimit)
                                        }
                                        .disabled(!manageCharging)
                                        .frame(width: 360)
                                        Spacer()
                                    }.frame(maxWidth: .infinity)
                                }
                                .padding(.bottom, 14)

                                Toggle(isOn: $inhibitChargingOnSleep) {
                                    Text(l10n.Button.Label.pauseChargingOnSleep)
                                }
                                .disabled(!manageCharging)
                                .padding(.bottom, 4)

                                VStack(alignment: .leading, spacing: 2) {
                                    Toggle(isOn: $dischargeBatteryWhenFull) {
                                        Text(l10n.Button.Label.dischargeBatterWhenOvercharged)
                                    }
                                    .disabled(!manageCharging)
                                    .onChange(of: dischargeBatteryWhenFull) { _, newValue in
                                        if newValue {
                                            disableSleepDuringDischarging = true
                                        }
                                    }
                                    Text(l10n.Button.Description.lidMustBeOpened)
                                        .offset(x: 19)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .settingDescription()
                                        .opacity(manageCharging ? 1 : 0.4)
                                }
                                Toggle(isOn: $disableSleepDuringDischarging) {
                                    Text(l10n.Button.Label.disableSleepWhileDischarging)
                                }
                            }
                            .padding()
                        }
                    }
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

    static let pane: Pane<Self> = Pane(
        identifier: identifier,
        title: L10n.Settings.Tab.Title.charging,
        toolbarIcon: NSImage(
            systemSymbolName: "bolt.badge.a",
            accessibilityDescription: L10n.Settings.Accessibility.Title.charging
        )!
    ) {
        Self()
    }

    static var identifier: NSToolbarItem.Identifier { .init("Charging") }
}

struct ChargingView_Previews: PreviewProvider {
    static var previews: some View {
        ChargingView()
    }
}
