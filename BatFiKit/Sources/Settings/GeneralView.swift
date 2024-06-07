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
import ServiceManagement
import SettingsKit
import SharedUI
import SwiftUI

struct GeneralView: View {
    @State private var automaticallyDownloadsUpdates: Bool = false

    @Default(.sendAnalytics) private var sendAnalytics
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.downloadBetaVersion) private var checkForBetaUpdates

    @Dependency(\.featureFlags) private var featureFlags
    @Dependency(\.updater) private var updater

    @Environment(\.openURL) private var openURL

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
                Toggle(l10n.Button.Label.automaticallyDownloadUpdates, isOn: $automaticallyDownloadsUpdates)
                    .onChange(of: automaticallyDownloadsUpdates) { newValue in
                        updater.setAutomaticallyDownloadsUpdates(newValue)
                    }
                Toggle(l10n.Button.Label.checkForBetaUpdates, isOn: $checkForBetaUpdates)
                    .onChange(of: checkForBetaUpdates) { checkForBetaUpdates in
                        if checkForBetaUpdates {
                            updater.checkForUpdates()
                        }
                    }
            }
            Section(title: l10n.Section.other, bottomDivider: true) {
                VStack(alignment: .leading) {
                    if featureFlags.isUsingBetaVersion() {
                        Toggle(l10n.Button.Label.sendAnalytics, isOn: .constant(true))
                            .disabled(true)
                        Text(l10n.Label.analyticsAreAlwaysOnDuringBeta).settingDescription()
                    } else {
                        Toggle(l10n.Button.Label.sendAnalytics, isOn: $sendAnalytics)
                    }
                }
            }
        }.onAppear {
            automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates()
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("General"),
        title: L10n.Settings.Tab.Title.general,
        toolbarIcon: NSImage(
            systemSymbolName: "gear",
            accessibilityDescription: L10n.Settings.Accessibility.Title.general
        )!
    ) {
        Self()
    }
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
