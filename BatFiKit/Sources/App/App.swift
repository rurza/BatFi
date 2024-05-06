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
import KeyboardShortcuts
import L10n
import MenuBuilder
import Notifications
import Onboarding
import Shared
import Settings
import StatusItemArrowKit

public final class BatFi: MenuControllerDelegate, StatusItemManagerDelegate, HelperConnectionManagerDelegate, Sendable {
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var settingsController = SettingsController()
    private lazy var persistenceManager = PersistenceManager()
    private lazy var magSafeColorManager = MagSafeColorManager()
    private lazy var analyticsManager = AnalyticsManager()
    private lazy var helperConnectionManager = HelperConnectionManager(delegate: self)

    private var chargingManager = ChargingManager()
    private var menuController: MenuController?
    private var notificationsManager: NotificationsManager?
    private var statusItemIconController: StatusItemManager?

    public var chargingModeManager: ChargingModeManager { chargingManager }

    private weak var aboutWindow: NSWindow?
    private weak var onboardingWindow: OnboardingWindow?
    private weak var arrowWindow: ArrowWindow?
    @Dependency(\.updater) private var updater
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.defaults) private var defaults
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.analyticsClient) private var analyticsClient
    @Dependency(\.featureFlags) private var featureFlags
    @Dependency(\.dockIcon) private var dockIcon

    public init() {}
    
    public func start(isBeta: Bool) {
        setFeatureFlags(beta: isBeta)
        analyticsManager.start(shouldEnable: isBeta || defaults.value(.sendAnalytics))
        _ = updater // initialize updater
        if defaults.value(.onboardingIsDone) {
            Task {
                await dockIcon.show(false)
                await setUpTheApp()
                helperConnectionManager.checkHelperHealth()
                observerKeyboardHotkeys()
            }
        } else {
            openOnboarding()
        }
    }

    public func willQuit() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            await analyticsClient.addBreadcrumb(category: .lifecycle, message: "XRPC hangs, timeout, the app should terminate")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        Task {
            await self.chargingManager.appWillQuit()
            await self.magSafeColorManager.appWillQuit()
            try? await self.helperClient.quitHelper()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    private func setUpTheApp() async {
            menuController = MenuController(statusItem: statusItem)
            await chargingManager.setUpObserving()
            persistenceManager.setUpObserving()
            await magSafeColorManager.setUpObserving()
            menuController?.delegate = self
            notificationsManager = NotificationsManager()
            statusItemIconController = StatusItemManager(statusItem: statusItem)
    }

    private func setFeatureFlags(
        beta isBeta: Bool
    ) {
        if isBeta {
            featureFlags.enableFeatureFlag(.beta)
        }
    }

    // MARK: - MenuControllerDelegate

    public func openSettings() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
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

    public func chargeToFull() {
        chargingManager.forceCharge()
    }

    public func dischargeBattery(to limit: Int) {
        chargingManager.dischargeBattery(to: limit)
    }

    public func stopOverride() {
        chargingManager.stopOverride()
    }

    public func openOnboarding() {
        Task {
            await dockIcon.show(true)

            if onboardingWindow == nil {
                let window = OnboardingWindow { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.setUpTheApp()
                        self.statusItemIconController?.delegate = self
                    }
                } onClose: { [weak self] in
                    Task {
                        await self?.dockIcon.show(false)
                    }
                }
                window.makeKeyAndOrderFront(nil)
                window.center()
                onboardingWindow = window
            } else {
                onboardingWindow?.makeKeyAndOrderFront(nil)
            }
            NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        }
    }

    // MARKL -
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

    private func observerKeyboardHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .dischargeBattery) { [weak self] in
            self?.dischargeBattery(to: 0)
        }
        KeyboardShortcuts.onKeyUp(for: .chargeToHundred) { [weak self] in
            self?.chargeToFull()
        }
        KeyboardShortcuts.onKeyUp(for: .stopOverride) { [weak self] in
            self?.stopOverride()
        }
        KeyboardShortcuts.onKeyUp(for: .inhibitCharging) { [weak self] in
            self?.chargingManager.inhibitCharging()
        }
    }

    public func statusItemIconDidAppear() {
        showStatusItemArrow()
        statusItemIconController?.delegate = nil
    }

    func showHelperIsNotInstalled() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.installHelperTroubleshooting
        alert.informativeText = L10n.Notifications.Alert.InformativeText.installHelperTroubleshooting
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openOnboarding)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        } else if response == .alertFirstButtonReturn {
            openOnboarding()
        }
    }
}
