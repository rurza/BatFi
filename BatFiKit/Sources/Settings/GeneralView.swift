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
    @Default(.monochromeStatusIcon) private var monochrom
    @Default(.showBatteryPercentageInStatusIcon) private var batteryPercentage
    @Default(.showDebugMenu) private var showDebugMenu
    
    @State private var automaticallyChecksForUpdates: Bool = false
    @State private var automaticallyDownloadsUpdates: Bool = false
    
    @Dependency(\.updater) private var updater

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(title: "General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
            }
            Section(title: "Status Icon", bottomDivider: true) {
                Toggle("Show monochrome icon", isOn: $monochrom)
                Toggle("Show battery percentage", isOn: $batteryPercentage)

            }
            Section(title: "App Updates") {
                Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                    .onChange(of: automaticallyChecksForUpdates) { newValue in
                        updater.setAutomaticallyChecksForUpdates(newValue)
                    }

                Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                    .disabled(!automaticallyChecksForUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { newValue in
                        updater.setAutomaticallyDownloadsUpdates(newValue)
                    }
            }
            Section(title: "Advanced") {
                Toggle("Show Debug menu", isOn: $showDebugMenu)
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
                systemSymbolName: "gear.circle.fill",
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
