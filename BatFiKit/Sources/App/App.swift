//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppCore
import Cocoa
import MenuBuilder
import Settings

@MainActor
public final class BatFi: MenuControllerDelegate {
    lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    lazy var settingsController = SettingsController()
    var chargingManager = ChargingManager()
    var menuController: MenuController?

    public init() { }

    public func start() {
        chargingManager.setUpObserving()
        statusItem.button?.image = NSImage(systemSymbolName: "minus.plus.batteryblock.fill", accessibilityDescription: "BatFi icon")
        menuController = MenuController(statusItem: statusItem)
        menuController?.delegate = self
    }

    public func willQuit() {
        chargingManager.appWillQuit()
    }

    // MARK: - MenuControllerDelegate
    func forceCharge() {
        chargingManager.chargeToFull()
    }

    func stopForceCharge() {
        chargingManager.turnOffChargeToFull()
    }

    func openSettings() {
        settingsController.openSettings()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }
}
