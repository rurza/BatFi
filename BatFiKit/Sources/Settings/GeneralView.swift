//
//  GeneralView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Clients
import Defaults
import Dependencies
import SwiftUI
import SettingsKit
import ServiceManagement

struct GeneralView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.monochromeStatusIcon) private var monochrom
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
            Section(title: "Menu Bar", bottomDivider: true) {
                //                Toggle("Hide status bar icon", isOn: $launchAtLogin)
                Toggle("Show monochrome icon", isOn: $monochrom)
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
        }.onAppear {
            automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates()
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates()
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("General"),
            title: "General",
            toolbarIcon: NSImage(systemSymbolName: "gear.circle.fill", accessibilityDescription: "General pane")!
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
