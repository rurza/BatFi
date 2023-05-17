//
//  App.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AboutKit
import AppCore
import Cocoa
import Dependencies
import MenuBuilder
import Notifications
import Settings
import UserNotifications

@MainActor
public final class BatFi: MenuControllerDelegate {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var settingsController = SettingsController()
    private var chargingManager = ChargingManager()
    private var menuController: MenuController?
    private var notificationsManager: NotificationsManager?
    private weak var aboutWindow: NSWindow?
    @Dependency(\.updater) private var updater

    public init() { }

    public func start() {
        chargingManager.setUpObserving()
        notificationsManager = NotificationsManager()
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

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    func openAbout() {
        if aboutWindow == nil {
            let about = AboutWindow(description: "Made with ❤️ and 🔋 by")
            about.makeKeyAndOrderFront(nil)
            self.aboutWindow = about
        } else {
            aboutWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
