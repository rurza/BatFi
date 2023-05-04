//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Cocoa
import Dependencies
import MenuBuilder

public final class BatFi {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    @Dependency(\.chargingClient) var chargingClient

    public init() { }

    public func start() {
        statusItem.button?.image = NSImage(systemSymbolName: "minus.plus.batteryblock.fill", accessibilityDescription: "BatFi icon")
        statusItem.menu = MenuFactory.standardMenu(
            disableCharging: {
                Task {
                    try await self.chargingClient.turnOffCharging()
                }
            }
        )
    }
}
