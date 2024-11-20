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

public final class BatFi: StatusItemManagerDelegate, HelperConnectionManagerDelegate, Sendable {
    private lazy var settingsController = SettingsController()
    private lazy var persistenceManager = PersistenceManager()
    private lazy var magSafeColorManager = MagSafeColorManager()
    private lazy var analyticsManager = AnalyticsManager()
    private lazy var helperConnectionManager = HelperConnectionManager(delegate: self)

    private var chargingManager = ChargingManager()
    private var notificationsManager: NotificationsManager?
    private var statusItemManager: StatusItemManager?

    public var chargingModeManager: ChargingModeManager { chargingManager }

    private weak var aboutWindow: NSWindow?
    private weak var onboardingWindow: OnboardingWindow?
    private weak var arrowWindow: ArrowWindow?
    @Dependency(\.analyticsClient) private var analyticsClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.dockIcon) private var dockIcon
    @Dependency(\.featureFlags) private var featureFlags
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.systemVersionClient) private var systemVersion
    @Dependency(\.updater) private var updater
    @Dependency(\.userNotificationsClient) private var userNotificationsClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.powerModeClient) private var powerModeClient


    public init() {}

    public func start(isBeta: Bool) {
        guard powerSourceClient.isRunningOnLaptop() else {
            showAppIsNotRunningOnLaptop()
            return
        }
        setFeatureFlags(beta: isBeta)
        analyticsManager.start(shouldEnable: isBeta || defaults.value(.sendAnalytics))
        _ = updater // initialize updater
        if defaults.value(.onboardingIsDone) {
            Task {
                await runMigration()
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

    public func shouldHandleReopen() {
        if !defaults.value(.showMenuBarIcon) {
            openSettings()
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
                        self.showStatusItemArrow()
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

    // MARK: -

    private func setUpTheApp() async {
        await chargingManager.setUpObserving()
        persistenceManager.setUpObserving()
        await magSafeColorManager.setUpObserving()

        notificationsManager = NotificationsManager()
        statusItemManager = StatusItemManager()
        statusItemManager?.delegate = self
    }

    private func runMigration() async {
        if systemVersion.currentSystemIsSequoiaOrNewer() && defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep) {
            defaults.setValue(.turnOnSystemChargeLimitingWhenGoingToSleep, value: false)
            try? await userNotificationsClient.showUserNotification(
                title: "System charge limit removed",
                body: "It looks like you're running on macOS 15. The \"Enable System charge limit 80% on sleep\" option was removed from this macOS",
                identifier: "software.micropixels.BatFi.migration.system_charge_limit",
                threadIdentifier: nil,
                delay: nil
            )
        }
    }

    private func setFeatureFlags(
        beta isBeta: Bool
    ) {
        if isBeta {
            featureFlags.enableFeatureFlag(.beta)
        }
    }

    @MainActor
    private func showStatusItemArrow() {
        if let statusItem = statusItemManager?.statusItem {
            let window = ArrowWindow(arrowSize: NSSize(width: 40, height: 120), statusItem: statusItem)
            arrowWindow = window
            window.show()
            Task {
                try await clock.sleep(for: .seconds(7))
                arrowWindow?.close()
            }
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
        KeyboardShortcuts.onKeyUp(for: .toggleLowPowerMode) { [weak self] in
            guard let self else { return }
            Task {
                guard let mode = try? await self.powerModeClient.getCurrentPowerMode() else { return }
                if mode != .low {
                    do {
                        try await self.powerModeClient.setPowerMode(.low)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.lowPowerModeOn,
                            body: "",
                            identifier: "low",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                } else {
                    do {
                        try await self.powerModeClient.setPowerMode(.normal)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.automaticPowerModeOn,
                            body: "",
                            identifier: "automatic",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                }
            }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleHighPowerMode) { [weak self] in
            guard let self else { return }
            Task {
                guard let mode = try? await self.powerModeClient.getCurrentPowerMode() else { return }
                if mode != .high {
                    do {
                        try await self.powerModeClient.setPowerMode(.high)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.highPowerModeOn,
                            body: "",
                            identifier: "high",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                } else {
                    do {
                        try await self.powerModeClient.setPowerMode(.normal)
                        try? await self.userNotificationsClient.showUserNotification(
                            title: L10n.Notifications.Notification.Title.automaticPowerModeOn,
                            body: "",
                            identifier: "automatic",
                            threadIdentifier: "powermode",
                            delay: nil
                        )
                    } catch { }
                }
            }
        }
    }

    public func statusItemIconDidAppear() {
        showStatusItemArrow()
        statusItemManager?.delegate = nil
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

    private func showAppIsNotRunningOnLaptop() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.notLaptop
        alert.informativeText = L10n.Notifications.Alert.InformativeText.notLaptop
        alert.addButton(withTitle: L10n.Menu.Label.quit)
        let response = alert.runModal()
        NSApp.terminate(nil)
    }
}
