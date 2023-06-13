//
//  NotificationsView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Defaults
import SettingsKit
import SwiftUI

struct NotificationsView: View {
    @Default(.showChargingStausChanged) var showChargingStausChanged

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(title: "Notifications", bottomDivider: true) {
                Toggle(isOn: $showChargingStausChanged) {
                    Text("Charging status has changed")
                }
            }
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Notifications"),
            title: "Notifications",
            toolbarIcon: NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Notifications pane")!
        ) {
            Self()
        }
    }()
}
