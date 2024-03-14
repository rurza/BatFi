//
//  AdvancedView.swift
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
    @Default(.temperatureSwitch) private var temperatureSwitch
    @Default(.disableSleep) private var disableAutomaticSleep
    @Default(.turnOnInhibitingChargingWhenGoingToSleep) private var inhibitChargingOnSleep
    @Default(.showGreenLightMagSafeWhenInhibiting) private var greenLight
    @Default(.downloadBetaVersion) private var checkForBetaUpdates
    @Default(.showDebugMenu) private var showDebugMenu
    @Default(.turnOnSystemChargeLimitingWhenGoingToSleep) private var enableSystemChargeLimitOnSleep

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
            Section(title: l10n.Section.other) {
                Toggle(l10n.Button.Label.checkForBetaUpdates, isOn: $checkForBetaUpdates)
                    .onChange(of: checkForBetaUpdates) { checkForBetaUpdates in
                        if checkForBetaUpdates {
                            updater.checkForUpdates()
                        }
                    }
                Toggle(l10n.Button.Label.debugMenu, isOn: $showDebugMenu)

            }
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("Advanved"),
        title: L10n.Settings.Tab.Title.advanced,
        toolbarIcon: NSImage(
            systemSymbolName: "gearshape.2",
            accessibilityDescription: L10n.Settings.Accessibility.Title.advanced
        )!
    ) {
        Self()
    }
}
