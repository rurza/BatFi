//
//  Settings.swift
//
//
//  Created by Adam on 05/05/2023.
//

import Cocoa
import KeyboardShortcuts
import License
import SettingsKit

@MainActor
public final class SettingsController {
    private let licenseModel: LicenseModel

    private lazy var settingsWindowController = SettingsWindowController(
        panes: [
            GeneralView.pane,
            ChargingView.pane,
            AutomationView.pane,
            MenubarView.pane,
            SettingsStatusIconView.pane,
            NotificationsView.pane,
            HotkeysView.pane,
            AdvancedView.pane,
            SettingsLicenseView.pane(licenseModel: licenseModel)
        ]
    )

    public init(licenseModel: LicenseModel) {
        self.licenseModel = licenseModel
    }

    public func openSettings() {
        settingsWindowController.show(pane: ChargingView.identifier)
    }

    public func openAutomationSettings() {
        settingsWindowController.show(pane: AutomationView.identifier)
    }
}

// MARK: -

public extension KeyboardShortcuts.Name {
    static let chargeToHundred = Self("chargeToHundred")
    static let dischargeBattery = Self("dischargeBattery")
    static let inhibitCharging = Self("inhibitCharging")
    static let stopOverride = Self("stopOverride")
    static let toggleHighPowerMode = Self("toogleHighPowerMode")
    static let toggleLowPowerMode = Self("toggleLowPowerMode")
}
