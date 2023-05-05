//
//  GeneralView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Defaults
import SwiftUI
import SettingsKit
import ServiceManagement

struct GeneralView: View {
    @Default(.launchAtLogin) private var launchAtLogin


    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(title: "General", bottomDivider: true) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                Toggle("Hide status bar icon", isOn: $launchAtLogin)
            }
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
