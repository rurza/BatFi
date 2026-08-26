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

@MainActor
public class NotificationsManager: NSObject {
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.updater) private var updater
    @Dependency(\.defaults) private var defaults
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.date) private var date
    @Dependency(\.userNotificationsClient) var userNotificationsClient
    @Dependency(\.persistence) var persistence
    @Dependency(\.licenseClient) private var licenseClient
    private lazy var center = UNUserNotificationCenter.current()
    private lazy var logger = Logger(category: "🔔")
    private var chargingModeTask: Task<Void, Never>?
    /// The last state a notification was actually posted for, so a re-emission of an unchanged
    /// one is not announced again. Cleared when observing stops, so re-enabling the setting
    /// announces the current state once.
    private var lastNotifiedChargingMode: AppChargingMode?
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
            for await (showBatteryLowNotification, powerSourceState, threshold) in combineLatest(
                defaults.observe(.showBatteryLowNotification),
                powerSourceClient.powerSourceChanges(),
                defaults.observe(.batteryLowNotificationThreshold)
            ).debounce(for: .seconds(5)) {
                guard showBatteryLowNotification else {
                    didShowLowBatteryNotification = false
                    continue
                }

                guard !powerSourceState.isCharging else {
                    if powerSourceState.batteryLevel > threshold || powerSourceState.isCharging {
                        didShowLowBatteryNotification = false
                    }
                    continue
                }

                if powerSourceState.batteryLevel <= threshold, !didShowLowBatteryNotification, powerSourceState.batteryLevel != 0 {
                    didShowLowBatteryNotification = true
                    await showBatteryIsLowNotification()
                }
            }
        }
        Task {
            for await (lastChargingReminderDate, showRemindersToDischargeAndChargeBattery, _) in combineLatest(
                    defaults.observe(.lastChargingReminderDate),
                    defaults.observe(.showRemindersToDischargeAndChargeBattery),
                    powerSourceClient.powerSourceChanges()
                    ) {
                guard showRemindersToDischargeAndChargeBattery else { continue }
                guard lastChargingReminderDate < date.now.addingTimeInterval(-60 * 60 * 24 * 3) else { continue }
                guard let values = try? await persistence.fullChargeAndDischargeWasInLast30Days() else { continue }
                guard !values.charge && !values.discharge else {
                    continue
                }
                do {
                    try await showBatteryCalibrationReminder()
                    defaults.setValue(.lastChargingReminderDate, value: date.now)
                } catch { }
            }
        }
    }

    // MARK: - Charging mode

    func startObservingChargingStateMode() {
        // Cancelled before it is replaced, or the old one keeps listening.
        //
        // `defaults.observe` yields the current value on subscribe and again on every write,
        // including a write of the same value, so this runs more than once per launch. The
        // assignment overwrote the reference without stopping the task behind it, leaving two
        // live subscribers to `appChargingModeDidChage()` — and every mode change then posted
        // its notification once per subscriber. Measured 2026-08-26: 13 state changes produced
        // **26** distinct notifications, an exact doubling, which is what the duplicate pairs in
        // Notification Center were. A third emission would have made it three.
        //
        // The identifiers are deliberately unique per notification (see
        // `UserNotificationsClient+Live`), so duplicates stack as separate banners rather than
        // collapsing into one — which is correct for genuine repeat events and merciless here.
        chargingModeTask?.cancel()
        chargingModeTask = Task {
            for await (chargingMode, manageCharging) in combineLatest(
                appChargingState.appChargingModeDidChage(),
                defaults.observe(.manageCharging)
            ) {
                guard chargingMode.mode != .initial,
                      manageCharging,
                      chargingMode.chargerConnected
                else { continue }
                // Only when the state actually changed.
                //
                // `combineLatest` emits whenever **either** side does, and re-emits the cached
                // value of the other — so every tick of `defaults.observe(.manageCharging)`
                // re-delivered a mode that had not changed, and each re-delivery posted its own
                // notification. `setAppChargingMode` already dedupes the mode stream, which is
                // why the duplicates were invisible from that end.
                //
                // Measured 2026-08-26 20:59:35: three notifications inside six milliseconds on
                // launch — "Charging to the limit" twice and then the drain — for two real
                // states. Identifiers are deliberately unique per notification, so duplicates
                // stack as separate banners rather than collapsing, which is right for genuine
                // repeat events and merciless for these.
                //
                // Compared on the whole `AppChargingMode` rather than on `mode`: the system
                // flags are part of what the sentence says, so a drain becoming a top-up is a
                // real change even though `mode` stays `.inhibit`.
                guard chargingMode != lastNotifiedChargingMode else { continue }
                lastNotifiedChargingMode = chargingMode
                logger.info("Should display notification")
                await showChargingStateModeDidChangeNotification(chargingMode)
            }
        }
    }

    func cancelObservingChargingStateMode() {
        lastNotifiedChargingMode = nil
        chargingModeTask?.cancel()
    }

    func showChargingStateModeDidChangeNotification(_ mode: AppChargingMode) async {
        guard (try? await licenseClient.cachedLicense()) != nil else { return }
        if await userNotificationsClient.requestAuthorization() == true {
            do {
                logger.debug("Adding notification request to the notification center")
                // Automation can override the configured limit. When it's active, show the
                // limit it actually applies and name the responsible rule.
                let automationLimit = await appChargingState.currentAutomationLimit()
                let effectiveLimit = automationLimit ?? defaults.value(.chargeLimit)
                let chargeLimitFraction = Double(effectiveLimit) / 100
                let automationRuleName = automationLimit != nil
                    ? (activeAutomationRuleName() ?? L10n.Automation.untitledRule)
                    : nil

                try await userNotificationsClient.showUserNotification(
                    title: L10n.Notifications.Notification.Subtitle.newMode(mode.stateDescription),
                    body: mode.stateDescription(
                        chargeLimitFraction: chargeLimitFraction,
                        automationRuleName: automationRuleName
                    ) ?? "",
                    identifier: "software.micropixels.BatFi.notifications.mode",
                    threadIdentifier: "Charging mode",
                    delay: 1.5
                )
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Name of the automation rule the engine currently considers active, or nil if none can
    /// be resolved. Empty names fall back to a generic label.
    private func activeAutomationRuleName() -> String? {
        guard let rule = AutomationEngine.activeRule(
            in: defaults.value(.automationRules),
            activeRuleID: defaults.value(.automationActiveRuleID)
        ) else { return nil }
        return rule.name.isEmpty ? L10n.Automation.untitledRule : rule.name
    }

    func showBatteryIsLowNotification() async {
        if await userNotificationsClient.requestAuthorization() == true {
            do {
                logger.debug("Adding notification request to the notification center")
                try await userNotificationsClient.showUserNotification(
                    title: L10n.Notifications.Notification.Title.lowBattery,
                    body: L10n.Notifications.Notification.Body.lowBattery,
                    identifier: "software.micropixels.BatFi.notifications.lowBattery", 
                    threadIdentifier: "Battery low",
                    delay: nil
                )
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func showBatteryCalibrationReminder() async throws {
        if await userNotificationsClient.requestAuthorization() == true {
            do {
                logger.debug("Adding battery calibration notification request to the notification center")
                try await userNotificationsClient.showUserNotification(
                    title: L10n.Notifications.Notification.Title.lowBattery,
                    body: L10n.Notifications.Notification.Body.lowBattery,
                    identifier: "software.micropixels.BatFi.notifications.calibration",
                    threadIdentifier: "Calibration",
                    delay: nil
                )
            } catch {
                logger.error("Notification request error: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    // MARK: - Optimized battery charging

    func startObservingOptimizedBatteryCharging() {
        // Same as `startObservingChargingStateMode` — the identical pattern, the identical
        // leak. Not observed doubling in the wild only because this state changes rarely.
        optimizedBatteryChargingTask?.cancel()
        optimizedBatteryChargingTask = Task {
            for await (powerState, manageCharging) in combineLatest(
                powerSourceClient.powerSourceChanges(),
                defaults.observe(.manageCharging)
            ).debounce(for: .seconds(1), clock: AnyClock(self.clock)) {
                guard manageCharging, lastAlertDate.timeIntervalSinceNow < -60 * 60 * 8 else { continue }
                if let optimizedBatteryChargingEngaged = powerState.optimizedBatteryChargingEngaged, optimizedBatteryChargingEngaged {
                    lastAlertDate = date.now
                    showOptimizedBatteryChargingIsTurnedOn()
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
        alert.messageText = L10n.Notifications.Alert.Title.optimizedChargingTurnedOn
        alert.informativeText = L10n.Notifications.Alert.InformativeText.optimizedChargingTurnedOn
        alert.showsSuppressionButton = true
        alert.suppressionButton?.target = self
        alert.suppressionButton?.action = #selector(supressionWasSelected(_:))
        alert.addButton(withTitle: L10n.Common.ok)
        alert.addButton(withTitle: L10n.Notifications.Alert.Button.Label.openSystemSettings)
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

extension NotificationsManager: @preconcurrency UNUserNotificationCenterDelegate {
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
