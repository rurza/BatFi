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
import Onboarding
import Settings
import StatusItemArrowKit

@MainActor
public final class BatFi: MenuControllerDelegate, StatusItemIconControllerDelegate {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var settingsController = SettingsController()
    private var chargingManager = ChargingManager()
    private var menuController: MenuController?
    private var notificationsManager: NotificationsManager?
    private var statusItemIconController: StatusItemIconController?
    private weak var aboutWindow: NSWindow?
    private weak var onboardingWindow: OnboardingWindow?
    private weak var arrowWindow: ArrowWindow?
    @Dependency(\.updater) private var updater
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.settingsDefaults) private var settingsDefaults

    public init() { }

    public func start() {
        _ = updater // initialize updater
        if settingsDefaults.onboardingIsDone(nil) {
            setUpTheApp()
        } else {
            openOnboarding()
        }
    }

    public func willQuit() {
        chargingManager.appWillQuit()
    }

    private func setUpTheApp() {
        statusItemIconController = StatusItemIconController(statusItem: statusItem)
        menuController = MenuController(statusItem: statusItem)
        chargingManager.setUpObserving()
        menuController?.delegate = self
        notificationsManager = NotificationsManager()
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

    public func openOnboarding() {
        if onboardingWindow == nil {
            let window = OnboardingWindow { [weak self] in
                guard let self else { return }
                Task {
                    self.setUpTheApp()
                    self.statusItemIconController?.delegate = self
                }
            }
            window.makeKeyAndOrderFront(nil)
            window.center()
            self.onboardingWindow = window
        } else {
            onboardingWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @MainActor
    private func showStatusItemArrow() {
        let window = ArrowWindow(arrowSize: NSSize(width: 40, height: 120), statusItem: statusItem)
        arrowWindow = window
        window.show()
         Task {
             try await clock.sleep(for: .seconds(7))
             arrowWindow?.close()
        }
    }

    public func statusItemIconDidAppear() {
        self.showStatusItemArrow()
        statusItemIconController?.delegate = nil
    }
}
