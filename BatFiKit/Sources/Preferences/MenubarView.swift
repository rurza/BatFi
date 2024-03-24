//
//  MenubarView.swift
//
//
//  Created by Adam on 24/03/2024.
//

import ComposableArchitecture
import L10n
import SettingsKit
import SwiftUI

struct MenubarView: View {
    @Perception.Bindable
    var store: StoreOf<PreferencesFeature>

    var body: some View {
        WithPerceptionTracking {
            let l10n = L10n.Settings.self
            Container(contentWidth: settingsContentWidth) {
                Section(title: l10n.Section.menu) {
                    Toggle(l10n.Button.Label.showBatteryChartInMenu, isOn: $store.showChart)
                    Toggle(l10n.Button.Label.showPowerDiagram, isOn: $store.showPowerDiagram)
                    HStack(alignment: .top) {
                        Toggle(l10n.Button.Label.showHighEnergyImpactProcesses, isOn: $store.showHighEnergyImpactProcesses)
                        Button(
                            action: {
                                store.send(.binding(.set(\.showingHighEnergyImpactSettingsView, true)))
                            },
                            label: {
                                Text(L10n.Menu.Label.settings)
                            }
                        )
                        .popover(isPresented: $store.showingHighEnergyImpactSettingsView) {
                            HighEnergyImpactSettingsView(store: store)
                        }
                    }
                }

                Section(title: l10n.Section.statusIcon, bottomDivider: true) {
                    Toggle(l10n.Button.Label.monochromeIcon, isOn: $store.monochromeStatusIcon)
                    Toggle(l10n.Button.Label.batteryPercentage, isOn: $store.showBatteryPercentageInStatusIcon)
                }
            }
        }
    }

    static func pane(store: StoreOf<PreferencesFeature>) -> Pane<Self> {
        Pane(
            identifier: NSToolbarItem.Identifier("Menubar"),
            title: L10n.Settings.Tab.Title.statusBar,
            toolbarIcon: NSImage(
                systemSymbolName: "menubar.rectangle",
                accessibilityDescription: L10n.Settings.Accessibility.Title.statusBar
            )!
        ) {
            Self(store: store)
        }
    }
}

#if DEBUG
#Preview {
    MenubarView(store: .init(initialState: .init(), reducer: PreferencesFeature.init))
}
#endif
