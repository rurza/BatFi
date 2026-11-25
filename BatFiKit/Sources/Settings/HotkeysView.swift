//
//  HotkeysView.swift
//
//
//  Created by Adam Różyński on 24/04/2024.
//

import Defaults
import DefaultsKeys
import KeyboardShortcuts
import L10n
import SettingsKit
import Shared
import SharedUI
import SwiftUI

struct HotkeysView: View {
    /// Observed rather than read once, so the row settles if the backend is first learned
    /// while this pane is open. It is the cache rather than a fetch because the window sizes
    /// itself from the pane's first layout; deciding from an async answer would draw the row
    /// and then leave a gap where it was. See `Defaults.Keys.lastKnownChargeBackend`.
    @Default(.lastKnownChargeBackend) private var lastKnownChargeBackend

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(label: { EmptyView() }) {
                HStack {
                    GroupBackground {
                        VStack(alignment: .center, spacing: 12) {
                            shortcut(label: L10n.Settings.Hotkey.Label.chargeToFull, key: .chargeToHundred)
                            shortcut(label: L10n.Settings.Hotkey.Label.discharge, key: .dischargeBattery)
                            if InhibitChargingShortcut.isOffered(rawBackend: lastKnownChargeBackend) {
                                shortcut(label: L10n.Settings.Hotkey.Label.inhibit, key: .inhibitCharging)
                            }
                            shortcut(label: L10n.Settings.Hotkey.Label.stopOverride, key: .stopOverride)
                            Divider()
                            shortcut(label: L10n.Settings.Hotkey.Label.toggleLowPowerMode, key: .toggleLowPowerMode)
                            shortcut(label: L10n.Settings.Hotkey.Label.toggleHighPowerMode, key: .toggleHighPowerMode)
                        }
                        .frame(width: 400)
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }

    }

    @ViewBuilder
    func shortcut(label: String, key: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 0)
            KeyboardShortcuts.Recorder(for: key)
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("Hotkeys"),
        title: L10n.Settings.Tab.Title.hotkeys,
        toolbarIcon: NSImage(
            systemSymbolName: "keyboard",
            accessibilityDescription: L10n.Settings.Accessibility.Title.hotkeys
        )!
    ) {
        Self()
    }
}

#Preview {
    HotkeysView()
}
