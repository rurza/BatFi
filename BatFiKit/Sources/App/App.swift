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
import L10n
import MenuBuilder
import Notifications
import Onboarding
import Shared
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
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.sentryClient) private var sentryClient

    public init() {}

    public func start() {
        #if DEBUG
        sentryClient.startSDK()
        #else
        if defaults.value(.sendAnalytics) {
            sentryClient.startSDK()
        }
        #endif
        _ = updater // initialize updater
        if defaults.value(.onboardingIsDone) {
            setUpTheApp()
            checkHelperHealth()
        } else {
            openOnboarding()
        }
    }

    public func willQuit() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            sentryClient.captureMessage("XRPC hangs, timeout, I will quit the app")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        Task {
            await self.chargingManager.appWillQuit()
            await self.magSafeColorManager.appWillQuit()
            try? await self.helperClient.quitHelper()
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

    func checkHelperHealth() {
        Task {
            let status = await helperClient.helperStatus()
            if status == .notRegistered {
                do {
                    try await helperClient.installHelper()
                } catch {
                    showHelperIsNotInstalled()
                }
            } else if status == .requiresApproval || status == .notFound {
                showHelperIsNotInstalled()
            } else if status == .enabled {
                do {
                    _ = try await helperClient.pingHelper()
                } catch {
                    showHelperIsNotInstalled()
                }
            }
        }
    }

    @MainActor
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
