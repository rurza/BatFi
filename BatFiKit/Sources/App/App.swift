//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppCore
import ClientsLive
import Cocoa
import Dependencies
import MenuBuilder
import Settings

@MainActor
public final class BatFi {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    @Dependency(\.helperClient) var helperClient
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

    public func willQuit() {
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await helperClient.turnOnAutoChargingMode(true)
            semaphore.signal()
        }
        semaphore.wait()
    }
}
