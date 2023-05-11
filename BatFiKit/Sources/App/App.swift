//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppCore
import Defaults
import ClientsLive
import Cocoa
import Dependencies
import MenuBuilder
import Settings

@MainActor
public final class BatFi {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var settingsController = SettingsController()
    var chargingManager = ChargingManager()
    lazy var helperManager = HelperManager()

    public init() { }

    public func start() {
//        if Defaults[.onboardingIsDone] {
        Task {
            try? helperManager.removeService()
            try await Task.sleep(for: .seconds(1))
            try? helperManager.registerService()
            chargingManager.setUpObserving()
        }

//        }
        statusItem.button?.image = NSImage(systemSymbolName: "minus.plus.batteryblock.fill", accessibilityDescription: "BatFi icon")
        statusItem.menu = MenuFactory.standardMenu(
            disableCharging: {
            },
            enableCharging: {
                
            },
            openSettings: { self.settingsController.openSettings() }
        )
    }

    public func willQuit() {
        chargingManager.appWillQuit()
    }
}
