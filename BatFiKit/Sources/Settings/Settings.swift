//
//  Settings.swift
//
//
//  Created by Adam on 05/05/2023.
//

import Cocoa
import KeyboardShortcuts
import SettingsKit

public final class SettingsController {
    private lazy var settingsWindowController = SettingsWindowController(
        panes: [
            GeneralView.pane,
            ChargingView.pane,
            MenubarView.pane,
            NotificationsView.pane,
            HotkeysView.pane,
            AdvancedView.pane,
            TipJarView.pane
        ]
    )

    public init() {}

    public func openSettings() {
        settingsWindowController.show(pane: ChargingView.identifier)
    }
}

// MARK: -

public extension KeyboardShortcuts.Name {
    static let chargeToHundred = Self("chargeToHundred")
    static let dischargeBattery = Self("dischargeBattery")
    static let inhibitCharging = Self("inhibitCharging")
    static let stopOverride = Self("stopOverride")
}
