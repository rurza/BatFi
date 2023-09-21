//
//  GeneralView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Clients
import Defaults
import Dependencies
import L10n
import SwiftUI
import SettingsKit
import ServiceManagement

struct GeneralView: View {
    @Default(.launchAtLogin) private var launchAtLogin

    @State private var automaticallyChecksForUpdates: Bool = false
    @State private var automaticallyDownloadsUpdates: Bool = false
    
    @Dependency(\.updater) private var updater

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.general) {
                Toggle(l10n.Button.Label.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }
            Section(title: l10n.Section.updates, bottomDivider: true) {
                Toggle(l10n.Button.Label.automaticallyCheckUpdates, isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { newValue in
                        updater.setAutomaticallyChecksForUpdates(newValue)
                    }

                Toggle(l10n.Button.Label.automaticallyDownloadUpdates, isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { newValue in
                        updater.setAutomaticallyDownloadsUpdates(newValue)
                    }

            }

        }.onAppear {
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates()
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates()
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("General"),
            title: L10n.Settings.Tab.Title.general,
            toolbarIcon: NSImage(
                systemSymbolName: "gear",
                accessibilityDescription: L10n.Settings.Accessibility.Title.general
            )!
        ) {
            Self()
        }

    }()
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
