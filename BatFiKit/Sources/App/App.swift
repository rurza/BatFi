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
import License
import MenuBuilder
import Notifications
import Onboarding
import Shared
import Settings
import StatusItemArrowKit

public final class BatFi: StatusItemManagerDelegate, HelperConnectionManagerDelegate, Sendable {
    private let licenseModel = LicenseModel()
    private lazy var settingsController = SettingsController(licenseModel: licenseModel)
    private lazy var persistenceManager = PersistenceManager()
    private lazy var magSafeColorManager = MagSafeColorManager()
    private lazy var analyticsManager = AnalyticsManager()
    private lazy var helperConnectionManager = HelperConnectionManager(delegate: self)

    private var chargingManager = ChargingManager()
    private var automationManager = AutomationManager()
    private var notificationsManager: NotificationsManager?
    private var statusItemManager: StatusItemManager?
    private var appDidLaunch: Bool = false

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
        Task {
            await chargingManager.setLicenseModel(licenseModel)
            guard powerSourceClient.isRunningOnLaptop() else {
                showAppIsNotRunningOnLaptop()
                return
            }
            setFeatureFlags(beta: isBeta)
            analyticsManager.start(shouldEnable: isBeta || defaults.value(.sendAnalytics))
            _ = updater // initialize updater
            if defaults.value(.onboardingIsDone) {
                await runMigration()
                dockIcon.show(false)
                await setUpTheApp()
                helperConnectionManager.checkHelperHealth()
                observerKeyboardHotkeys()
                appDidLaunch = true
                if await !licenseModel.verifyCachedLicense() {
                    licenseModel.openLicenseWindow()
                }
            } else {
                openOnboarding()
            }
        }
    }

    public func willQuit() {
        Task {
            // Five seconds, not one. The work this races now does materially more than it
            // did: `restoreSystemDefaults()` makes several PowerUI round trips, can spend
            // up to ~2 s reopening a dropped SMC connection, and may re-probe the whole
            // nine-key table to decide whether a firmware charge band is held. Losing that
            // race under `.firmwareRange` leaves the band armed in hardware with nothing
            // running that knows about it. Still well inside launchd's terminate window,
            // and `ListenerDelegate` now restores on connection loss as a second net.
            try? await Task.sleep(for: .seconds(5))
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
        if !defaults.value(.showMenuBarIcon) && appDidLaunch {
            openSettings()
        }
    }

    public func handleOpeningURL(_ url: URL) {
        do {
            let key = try URLParser.parseURL(url)
            licenseModel.license = key
            licenseModel.verifyLicenseButtonClicked()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Can't use this link"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }

    // MARK: - MenuControllerDelegate

    public func openSettings() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        settingsController.openSettings()
    }

    public func openAutomationSettings() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        settingsController.openAutomationSettings()
    }

    /// Reached from the status item's warning row, so it is always available even after the
    /// once-per-launch modal has been spent.
    public func showHelperTroubleshooting() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        showHelperIsNotResponding()
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
        Task { [weak self] in
            guard let self else { return }
            dockIcon.show(true)
            // Onboarding runs its own helper UI; a modal stacked on top of it helps nobody.
            helperConnectionManager.suppressesGuidance = true

            if onboardingWindow == nil {
                let window = OnboardingWindow(licenseModel: licenseModel) { [weak self] in
                    guard let self else { return }
                    Task {
                        await self.setUpTheApp()
                        self.showStatusItemArrow()
                    }
                } onClose: { [weak self] in
                    Task {
                        self?.helperConnectionManager.suppressesGuidance = false
                        self?.dockIcon.show(false)
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
        await automationManager.setUpObserving()
        persistenceManager.setUpObserving()
        await magSafeColorManager.setUpObserving()

        if notificationsManager == nil {
            notificationsManager = NotificationsManager()
        }
        if statusItemManager == nil {
            statusItemManager = StatusItemManager(licenseModel: licenseModel)
            statusItemManager?.delegate = self
        }
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
            Task { [weak self] in
                try await self?.clock.sleep(for: .seconds(7))
                self?.arrowWindow?.close()
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
                guard let result = try? await self.powerModeClient.getCurrentPowerMode() else { return }
                let highPowerIsAvailable = result.1
                if result.0 != .low {
                    do {
                        try await self.powerModeClient.setPowerMode(.low, !highPowerIsAvailable)
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
                        try await self.powerModeClient.setPowerMode(.normal, !highPowerIsAvailable)
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
                guard let result = try? await self.powerModeClient.getCurrentPowerMode(), result.1 else {
                    try? await self.userNotificationsClient.showUserNotification(
                        title: L10n.Notifications.Notification.Title.highPowerModeUnsupported,
                        body: "",
                        identifier: "high",
                        threadIdentifier: "powermode",
                        delay: nil
                    )
                    return
                }
                if result.0 != .high {
                    do {
                        try await self.powerModeClient.setPowerMode(.high, false)
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
                        try await self.powerModeClient.setPowerMode(.normal, false)
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

    /// Distinct from `showHelperIsNotInstalled()` on purpose: in this state the helper *is*
    /// installed and approved, and telling the user to install it again sends them looking
    /// for a problem that isn't there.
    func showHelperIsNotResponding() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.helperNotResponding
        alert.informativeText = L10n.Notifications.Alert.InformativeText.helperNotResponding
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.close)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        }
    }

    private func showAppIsNotRunningOnLaptop() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = L10n.Notifications.Alert.Title.notLaptop
        alert.informativeText = L10n.Notifications.Alert.InformativeText.notLaptop
        alert.addButton(withTitle: L10n.Menu.Label.quit)
        _ = alert.runModal()
        NSApp.terminate(nil)
    }
}
