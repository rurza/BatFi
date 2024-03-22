//
//  NotificationsManager.swift
//
//
//  Created by Adam on 17/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Cocoa
import DefaultsKeys
import Dependencies
import L10n
import os
import UserNotifications

private let optimizedBatteryChargingCategoryIdentifier = "OPTIMIZED_BATTERY_CHARGING"
private let settingsActionIdentifier = "SETTINGS_ACTION"

public class NotificationsManager: NSObject {
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.updater) private var updater
    @Dependency(\.defaults) private var defaults
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.date) private var date
    private lazy var center = UNUserNotificationCenter.current()
    private lazy var logger = Logger(category: "🔔")
    private var chargingModeTask: Task<Void, Never>?
    private var optimizedBatteryChargingTask: Task<Void, Never>?
    private var lastAlertDate: Date = .distantPast
    private var didShowLowBatteryNotification = false

    override public init() {
        super.init()
        center.delegate = self
        setUpObserving()
    }

    func setUpObserving() {
        Task {
            for await showChargingStausChanged in defaults.observe(.showChargingStausChanged) {
                if showChargingStausChanged {
                    startObservingChargingStateMode()
                } else {
                    cancelObservingChargingStateMode()
                }
            }
        }
        Task {
            for await showOptimizedBatteryCharging in defaults.observe(.showOptimizedBatteryCharging) {
                if showOptimizedBatteryCharging {
                    startObservingOptimizedBatteryCharging()
                } else {
                    cancelObservingOptimizedBatteryCharging()
                }
            }
        }

        Task {
            for await (showBatteryLowNotification, powerSourceState) in combineLatest(
                defaults.observe(.showBatteryLowNotification),
                powerSourceClient.powerSourceChanges()
            ) {
                let batteryLimit = 20
                guard showBatteryLowNotification, !powerSourceState.isCharging else {
                    if powerSourceState.batteryLevel > batteryLimit {
                        didShowLowBatteryNotification = false
                    }
                    continue
                }
                if powerSourceState.batteryLevel <= batteryLimit, !didShowLowBatteryNotification {
                    didShowLowBatteryNotification = true
                    await showBatteryIsLowNotification()
                }
            }
        }
    }

    // MARK: - Charging mode

    func startObservingChargingStateMode() {
        chargingModeTask = Task {
            for await (chargingMode, manageCharging) in combineLatest(
                appChargingState.observeChargingStateMode(),
                defaults.observe(.manageCharging)
            ) {
                guard chargingMode != .chargerNotConnected,
                      chargingMode != .initial,
                      manageCharging else { continue }
                logger.info("Should display notification")
                await showChargingStateModeDidChangeNotification(chargingMode)
            }
        }
    }

    func cancelObservingChargingStateMode() {
        chargingModeTask?.cancel()
    }

    func showChargingStateModeDidChangeNotification(_ mode: AppChargingMode) async {
        if await requestAuthorization() == true {
            logger.info("permission granted, should dispatch the notification")
            center.removeAllPendingNotificationRequests()
            let content = UNMutableNotificationContent()
            content.subtitle = L10n.Notifications.Notification.Subtitle.newMode(mode.stateDescription)
            let chargeLimitFraction = Double(defaults.value(.chargeLimit)) / 100
            if let description = mode.stateDescription(chargeLimitFraction: chargeLimitFraction) {
                content.body = description
            } else {
                content.body = ""
            }
            content.interruptionLevel = .active // to show the notification
            content.threadIdentifier = "Charging mode"
            let request = UNNotificationRequest(
                identifier: "software.micropixels.BatFi.notifications.mode",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
            )

            do {
                logger.debug("Adding notification request to the notification center")
                try await center.add(request)
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func showBatteryIsLowNotification() async {
        if await requestAuthorization() == true {
            logger.info("permission granted, should dispatch the notification")
            let content = UNMutableNotificationContent()
            content.title = L10n.Notifications.Notification.Title.lowBattery
            content.body = L10n.Notifications.Notification.Body.lowBattery
            content.threadIdentifier = "Battery low"

            content.interruptionLevel = .active // to show the notification
            let request = UNNotificationRequest(
                identifier: "software.micropixels.BatFi.notifications.lowBattery",
                content: content,
                trigger: nil
            )
            do {
                logger.debug("Adding notification request to the notification center")
                try await center.add(request)
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Optimized battery charging

    func startObservingOptimizedBatteryCharging() {
        optimizedBatteryChargingTask = Task {
            for await (powerState, manageCharging) in combineLatest(
                powerSourceClient.powerSourceChanges(),
                defaults.observe(.manageCharging)
            ).debounce(for: .seconds(1), clock: AnyClock(self.clock)) {
                guard manageCharging, lastAlertDate.timeIntervalSinceNow < -60 * 60 * 8 else { continue }
                if powerState.optimizedBatteryChargingEngaged {
                    lastAlertDate = date.now
                    await showOptimizedBatteryChargingIsTurnedOn()
                }
            }
        }
    }

    func cancelObservingOptimizedBatteryCharging() {
        optimizedBatteryChargingTask?.cancel()
    }

    @MainActor
    func showOptimizedBatteryChargingIsTurnedOn() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Optimized battery charging is turned ON."
        alert.informativeText = "The app won't work properly with it. \nDisable it by clicking the info icon next to the \"Battery Health\" in System Settings."
        alert.showsSuppressionButton = true
        alert.suppressionButton?.target = self
        alert.suppressionButton?.action = #selector(supressionWasSelected(_:))
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "System Settings…")
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }
    }

    @objc
    func supressionWasSelected(_ sender: NSButton) {
        defaults.setValue(.showOptimizedBatteryCharging, value: !(sender.state == .on))
    }

    // MARK: - Helpers

    func requestAuthorization() async -> Bool? {
        try? await center.requestAuthorization(options: [.alert, .sound])
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    public func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer {
            completionHandler()
        }
        if response.notification.request.identifier == updateNotificationIdentifier,
           response.actionIdentifier == UNNotificationDefaultActionIdentifier
        {
            // If the notificaton is clicked on, make sure we bring the update in focus
            // If the app is terminated while the notification is clicked on,
            // this will launch the application and perform a new update check.
            // This can be more likely to occur if the notification alert style is Alert rather than Banner
            updater.checkForUpdates()
        } else if response.actionIdentifier == settingsActionIdentifier {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        }
    }
}
