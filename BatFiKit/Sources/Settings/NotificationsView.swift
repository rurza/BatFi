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
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Section.notifications, bottomDivider: true) {
                Toggle(isOn: $showChargingStausChanged) {
                    Text(l10n.Button.Label.chargingStatusDidChange)
                }
            }
            Section(title: l10n.Section.alerts) {
                Toggle(isOn: $showOptimizedBatteryCharging) {
                    Text(l10n.Button.Label.showAlertsWhenOptimizedChargingIsEngaged)
                }
            }
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("notifications"),
            title: L10n.Settings.Tab.Title.notifications,
            toolbarIcon: NSImage(
                systemSymbolName: "bell.badge.fill",
                accessibilityDescription: L10n.Settings.Accessibility.Title.notifications
            )!
        ) {
            Self()
        }
    }()
}
