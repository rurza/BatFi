//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Cocoa
import Dependencies
import MenuBuilder
import Settings

public final class BatFi {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    @Dependency(\.chargingClient) var chargingClient
    lazy var settingsController = SettingsController()

    public init() { }

    public func start() {
        statusItem.button?.image = NSImage(systemSymbolName: "minus.plus.batteryblock.fill", accessibilityDescription: "BatFi icon")
        statusItem.menu = MenuFactory.standardMenu(
            disableCharging: {
                Task {
                    try await self.chargingClient.turnOffCharging()
                }
            },
            enableCharging: {
                Task {
                    try await self.chargingClient.turnOnAutoChargingMode()
                }
            },
            openSettings: { self.settingsController.openSettings() }
        )
    }

    public func appWillQuit() {
        #warning("implement")
    }
}
