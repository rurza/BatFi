//
//  AdvancedView.swift
//
//
//  Created by Adam on 23/03/2024.
//

import AppShared
import Clients
import ComposableArchitecture
import L10n
import SettingsKit
import SwiftUI

struct AdvancedView: View {

    @Perception.Bindable
    var store: StoreOf<PreferencesFeature>

    var body: some View {
        WithPerceptionTracking {
            let l10n = L10n.Settings.self
            Container(contentWidth: settingsContentWidth) {
                Section(title: l10n.Section.charging, bottomDivider: true) {
                    Toggle(isOn: $store.temperatureSwitch) {
                        Text(l10n.Button.Label.turnOffChargingWhenBatteryIsHot)
                            .help(l10n.Button.Tooltip.turnOffChargingWhenBatteryIsHot)
                    }

                    Toggle(isOn: $store.disableSleep) {
                        Text(l10n.Button.Label.disableAutomaticSleep)
                            .help(l10n.Button.Tooltip.disableAutomaticSleep)
                    }

                    Toggle(isOn: $store.inhibitChargingOnSleep) {
                        Text(l10n.Button.Label.pauseChargingOnSleep)
                    }
                    .disabled(store.enableSystemChargeLimitOnSleep)

                    Toggle(isOn: $store.enableSystemChargeLimitOnSleep) {
                        Text(l10n.Button.Label.enableSystemChargeLimitOnSleep)
                    }
                    .disabled(store.inhibitChargingOnSleep)

                    Toggle(isOn: $store.magsafeUseGreenLightWhenInhibiting) {
                        Text(l10n.Button.Label.magsafeUseGreenLight)
                    }
                }
                Section(title: l10n.Section.other) {
                    Toggle(l10n.Button.Label.checkForBetaUpdates, isOn: $store.checkForBetaUpdates)
                    Toggle(l10n.Button.Label.debugMenu, isOn: $store.showDebugMenu)
                }
            }
        }
    }

    static func pane(store: StoreOf<PreferencesFeature>) -> Pane<Self> {
        Pane(
            identifier: NSToolbarItem.Identifier("Advanved"),
            title: L10n.Settings.Tab.Title.advanced,
            toolbarIcon: NSImage(
                systemSymbolName: "gearshape.2",
                accessibilityDescription: L10n.Settings.Accessibility.Title.advanced
            )!
        ) {
            Self(store: store)
        }
    }
}

#if DEBUG
#Preview {
    AdvancedView(store: .init(initialState: .init(), reducer: PreferencesFeature.init))
}
#endif
