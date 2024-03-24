//
//  ChargingView.swift
//
//
//  Created by Adam on 23/03/2024.
//

import AppShared
import ComposableArchitecture
import L10n
import SettingsKit
import SwiftUI

struct ChargingView: View {
    @Perception.Bindable
    var store: StoreOf<PreferencesFeature>

    @Dependency(\.percentageFormatter) var percentageFormatter

    var body: some View {
        WithPerceptionTracking {
            VStack(alignment: .leading, spacing: 0) {
                Container(contentWidth: settingsContentWidth) {
                    Section(bottomDivider: true) {
                        EmptyView()
                    } content: {
                        let l10n = L10n.Settings.self
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Toggle(isOn: $store.manageCharging) {
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
                                        let label = l10n.Slider.Label
                                            .turnOffChargingAt(percentageFormatter.string(store.chargeLimit))
                                        Text(label)
                                            .foregroundColor(store.manageCharging ? .primary : .secondary)
                                        HStack {
                                            Slider(value: .convert(from: $store.chargeLimit), in: 60 ... 90, step: 5) {
                                                EmptyView()
                                            } minimumValueLabel: {
                                                Text("60%")
                                            } maximumValueLabel: {
                                                Text("90%")
                                            }
                                            .disabled(!store.manageCharging)
                                            .frame(width: 340)
                                            Spacer()
                                        }.frame(maxWidth: .infinity)
                                    }
                                    .padding(.bottom, 14)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Toggle(isOn: $store.dischargeBatterWhenOvercharged) {
                                            Text(l10n.Button.Label.dischargeBatterWhenOvercharged)
                                                .withBetaLabel(disabled: !store.manageCharging)
                                                .help(l10n.Button.Tooltip.dischargeBatterWhenOvercharged)
                                        }
                                        .disabled(!store.manageCharging)
                                        Text(l10n.Button.Description.lidMustBeOpened)
                                            .settingDescription()
                                            .opacity(store.manageCharging ? 1 : 0.4)
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
    }

    static func pane(store: StoreOf<PreferencesFeature>) -> Pane<Self> {
        Pane(
            identifier: identifier,
            title: L10n.Settings.Tab.Title.charging,
            toolbarIcon: NSImage(
                systemSymbolName: "bolt.badge.a",
                accessibilityDescription: L10n.Settings.Accessibility.Title.charging
            )!
        ) {
            Self(store: store)
        }
    }

    static var identifier: NSToolbarItem.Identifier { .init("Charging") }
}

#if DEBUG
#Preview {
    ChargingView(store: .init(initialState: .init(), reducer: PreferencesFeature.init))
}
#endif
