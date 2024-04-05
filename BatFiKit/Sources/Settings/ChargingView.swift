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
    @Default(.chargeLimit) private var chargeLimit
    @Default(.manageCharging) private var manageCharging
    @Default(.allowDischargingFullBattery) private var dischargeBatteryWhenFull

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
                            .modify { view in
                                if #available(macOS 14.0, *) {
                                    view.controlSize(.extraLarge)
                                } else {
                                    view.controlSize(.large)
                                }
                            }
                            Text(l10n.Button.Label.automaticallyManageCharging)
                        }
                        .toggleStyle(.switch)
                        .padding(.bottom, 20)
                        .padding(.top, 10)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
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
                                            Text("50%")
                                        } maximumValueLabel: {
                                            Text("90%")
                                        }
                                        .disabled(!manageCharging)
                                        .frame(width: 360)
                                        Spacer()
                                    }.frame(maxWidth: .infinity)
                                }
                                .padding(.bottom, 14)

                                VStack(alignment: .leading, spacing: 2) {
                                    Toggle(isOn: $dischargeBatteryWhenFull) {
                                        Text(l10n.Button.Label.dischargeBatterWhenOvercharged)
                                            .withBetaLabel(disabled: !manageCharging)
                                            .help(l10n.Button.Tooltip.dischargeBatterWhenOvercharged)
                                    }
                                    .disabled(!manageCharging)
                                    Text(l10n.Button.Description.lidMustBeOpened)
                                        .settingDescription()
                                        .opacity(manageCharging ? 1 : 0.4)
                                }
                            }
                            .padding(4)
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
