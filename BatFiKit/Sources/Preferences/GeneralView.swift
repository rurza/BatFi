//
//  GeneralView.swift
//
//
//  Created by Adam on 23/03/2024.
//

import Clients
import ComposableArchitecture
import L10n
import SettingsKit
import SwiftUI

public struct GeneralView: View {

    @Perception.Bindable
    var store: StoreOf<PreferencesFeature>

    public var body: some View {
        WithPerceptionTracking {
            let l10n = L10n.Settings.self
            Container(contentWidth: settingsContentWidth) {
                Section(title: l10n.Section.general) {
                    Toggle(l10n.Button.Label.launchAtLogin, isOn: $store.launchAtLogin)
                }
                Section(title: l10n.Section.updates, bottomDivider: true) {
                    Toggle(l10n.Button.Label.automaticallyCheckUpdates, isOn: $store.automaticallyChecksForUpdates)
                    Toggle(l10n.Button.Label.automaticallyDownloadUpdates, isOn: $store.automaticallyDownloadsUpdates)
                        .disabled(!store.automaticallyChecksForUpdates)
                }
            }
        }

    }

    public static func pane(store: StoreOf<PreferencesFeature>) -> Pane<Self> {
        Pane(
            identifier: NSToolbarItem.Identifier("General"),
            title: L10n.Settings.Tab.Title.general,
            toolbarIcon: NSImage(
                systemSymbolName: "gear",
                accessibilityDescription: L10n.Settings.Accessibility.Title.general
            )!
        ) {
            Self(store: store)
        }
    }
}

#if DEBUG
#Preview {
    GeneralView(store: .init(initialState: .init(), reducer: PreferencesFeature.init))
}
#endif
