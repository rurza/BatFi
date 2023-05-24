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

@MainActor
public final class BatFi: MenuControllerDelegate {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var settingsController = SettingsController()
    private var chargingManager = ChargingManager()
    private var menuController: MenuController?
    private var notificationsManager: NotificationsManager?
    private var statusItemIconController: StatusItemIconController?
    private weak var aboutWindow: NSWindow?
    @Dependency(\.updater) private var updater

    public init() { }

    public func start() {
        _ = updater // initialize updater
        chargingManager.setUpObserving()
        statusItemIconController = StatusItemIconController(statusItem: statusItem)
        menuController = MenuController(statusItem: statusItem)
        menuController?.delegate = self
        notificationsManager = NotificationsManager()
    }

    public func willQuit() {
        chargingManager.appWillQuit()
    }

    // MARK: - MenuControllerDelegate
    public func forceCharge() {
        chargingManager.chargeToFull()
    }

    public func stopForceCharge() {
        chargingManager.turnOffChargeToFull()
    }

    public func openSettings() {
        settingsController.openSettings()
    }

    public func quitApp() {
        NSApp.terminate(nil)
    }

    public func checkForUpdates() {
        updater.checkForUpdates()
    }

    public func openAbout() {
        if aboutWindow == nil {
            let about = AboutWindow(description: "Made with ❤️ and 🔋 by")
            about.makeKeyAndOrderFront(nil)
            self.aboutWindow = about
        } else {
            aboutWindow?.makeKeyAndOrderFront(nil)
        }
    }
}
