//
//  Settings.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Cocoa
import SettingsKit

public final class SettingsController {
    private lazy var settingsWindowController = SettingsWindowController(
        panes: [
            GeneralView.pane,
            ChargingView.pane,
            NotificationsView.pane
        ]
    )

    public init() { }

    public func openSettings() {
        settingsWindowController.show()
    }
}
