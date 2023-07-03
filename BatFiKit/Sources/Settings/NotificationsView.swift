//
//  NotificationsView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Defaults
import L10n
import SettingsKit
import SwiftUI

struct NotificationsView: View {
    @Default(.showChargingStausChanged) private var showChargingStausChanged
    @Default(.showOptimizedBatteryCharging) private var showOptimizedBatteryCharging

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(title: "Notifications", bottomDivider: true) {
                Toggle(isOn: $showChargingStausChanged) {
                    Text("Charging status has changed")
                }
            }
            Section(title: "Alerts") {
                Toggle(isOn: $showOptimizedBatteryCharging) {
                    Text("Show alert when the optimized battery charging is engaged")
                }
            }
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier(L10n.Settings.Tab.Title.notifications),
            title: "Notifications",
            toolbarIcon: NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Notifications pane")!
        ) {
            Self()
        }
    }()
}
