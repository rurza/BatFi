//
//  App.swift
//
//
//  Created by Adam on 02/05/2023.
//

import About
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
    private lazy var persistenceManager = PersistenceManager()
    private lazy var magSafeColorManager = MagSafeColorManager()
    private var chargingManager = ChargingManager()
    private var menuController: MenuController?
    private var notificationsManager: NotificationsManager?
    private var statusItemIconController: StatusItemIconController?

    private weak var aboutWindow: NSWindow?
    private weak var onboardingWindow: OnboardingWindow?
    private weak var arrowWindow: ArrowWindow?
    @Dependency(\.updater) private var updater
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.defaults) private var defaults
    @Dependency(\.helperManager) private var helperManager

    public init() {}

    public func start() {
        _ = updater // initialize updater
        if defaults.value(.onboardingIsDone) {
            setUpTheApp()
        } else {
            openOnboarding()
        }
    }

    public func willQuit() {
        Task(priority: .userInitiated) {
            await chargingManager.appWillQuit()
            await magSafeColorManager.appWillQuit()
            try? await helperManager.quitHelper()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func setUpTheApp() {
        statusItemIconController = StatusItemIconController(statusItem: statusItem)
        menuController = MenuController(statusItem: statusItem)
        chargingManager.setUpObserving()
        persistenceManager.setUpObserving()
        magSafeColorManager.setUpObserving()
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
            let about = presentAboutWindow()
            aboutWindow = about
        } else {
            aboutWindow?.orderFrontRegardless()
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
            window.orderFrontRegardless()
            window.center()
            onboardingWindow = window
        } else {
            onboardingWindow?.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
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
        showStatusItemArrow()
        statusItemIconController?.delegate = nil
    }
}
