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
import Shared
import SwiftUI

struct AdvancedView: View {
    @Default(.temperatureSwitch) private var temperatureSwitch
    @Default(.disableSleep) private var disableAutomaticSleep
    @Default(.showDebugMenu) private var showDebugMenu

    @Dependency(\.updater) private var updater
    @Dependency(\.chargingClient) private var chargingClient

    /// Whether this Mac can stop charging on demand, as of the last time the helper was
    /// asked. Read from the cache rather than the live fetch because the hot-battery
    /// toggle is *hidden* when it cannot fire, and `SettingsWindowController` sizes its
    /// window once from `fittingSize` before any fetch can answer — so a control that
    /// disappears afterwards leaves a gap the window can never close.
    @Default(.lastKnownCanPauseCharging) private var canPauseChargingCache

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.charging, bottomDivider: true) {
                // Absent where the firmware holds charging at a percentage instead of
                // stopping it: there is no "stop now" for the cutout to call. This toggle
                // defaults to **on**, so without the gate it was the one default-on
                // setting in the app that could quietly do nothing at 45 °C.
                if !hotBatteryCutoffUnavailable {
                    Toggle(isOn: $temperatureSwitch) {
                        Text(l10n.Button.Label.turnOffChargingWhenBatteryIsHot)
                            .help(l10n.Button.Tooltip.turnOffChargingWhenBatteryIsHot)
                    }
                }

                Toggle(isOn: $disableAutomaticSleep) {
                    Text(l10n.Button.Label.disableAutomaticSleep)
                        .help(l10n.Button.Tooltip.disableAutomaticSleep)
                }

                MagSafeGreenLightToggle()
            }
            Section(title: l10n.Section.other) {
                Toggle(l10n.Button.Label.debugMenu, isOn: $showDebugMenu)
            }
        }
        .task {
            // Refreshes the cache the toggle above renders from. The Charging pane writes
            // the same key; whichever pane the user opens first keeps it current.
            guard let fresh = try? await chargingClient.chargingDiagnostics() else { return }
            guard let backend = ChargeBackend(rawValue: fresh.backend) else { return }
            canPauseChargingCache = backend.canPauseChargingOnDemand
        }
    }

    private var hotBatteryCutoffUnavailable: Bool { !canPauseChargingCache }

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
