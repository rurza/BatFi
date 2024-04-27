//
//  HotkeysView.swift
//
//
//  Created by Adam Różyński on 24/04/2024.
//

import Defaults
import KeyboardShortcuts
import L10n
import SettingsKit
import SharedUI
import SwiftUI

struct HotkeysView: View {

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(label: { EmptyView() }) {
                HStack {
                    GroupBackground {
                        VStack(alignment: .center, spacing: 12) {
                            shortcut(label: L10n.Settings.Hotkey.Label.chargeToFull, key: .chargeToHundred)
                            shortcut(label: L10n.Settings.Hotkey.Label.discharge, key: .dischargeBattery)
                            shortcut(label: L10n.Settings.Hotkey.Label.inhibit, key: .inhibitCharging)
                            shortcut(label: L10n.Settings.Hotkey.Label.stopOverride, key: .stopOverride)
                        }
                        .frame(maxWidth: 380)
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
            systemSymbolName: "command.square",
            accessibilityDescription: L10n.Settings.Accessibility.Title.hotkeys
        )!
    ) {
        Self()
    }
}

#Preview {
    HotkeysView()
}
