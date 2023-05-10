//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppCore
import Cocoa
import Dependencies
import MenuBuilder
import Settings

@MainActor
public final class BatFi {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    @Dependency(\.chargingClient) var chargingClient
    lazy var settingsController = SettingsController()
    var chargingManager: ChargingManager!

    public init() { }

    public func start() {
        chargingManager = ChargingManager()
        statusItem.button?.image = NSImage(systemSymbolName: "minus.plus.batteryblock.fill", accessibilityDescription: "BatFi icon")
        statusItem.menu = MenuFactory.standardMenu(
            disableCharging: {
            },
            enableCharging: {
                
            },
            openSettings: { self.settingsController.openSettings() }
        )
    }

    public func appWillQuit() {
        #warning("implement")
    }
}
