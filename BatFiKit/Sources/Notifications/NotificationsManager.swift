//
//  NotificationsManager.swift
//  
//
//  Created by Adam on 17/05/2023.
//

import AppShared
import AsyncAlgorithms
import Foundation
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import os
import UserNotifications

public class NotificationsManager: NSObject {
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.updater) private var updater
    @Dependency(\.defaults) private var defaults
    private lazy var center = UNUserNotificationCenter.current()
    private var task: Task<Void, Never>?
    private lazy var logger = Logger(category: "🔔")

    public override init() {
        super.init()
        center.delegate = self
        setUpObserving()
    }

    func setUpObserving() {
        Task {
            for await showNotifications in Defaults.updates(.showChargingStausChanged) {
                if showNotifications {
                    startObservingChargingStateMode()
                } else {
                    cancelObservingChargingStateMode()
                }
            }
        }
    }
    
    func startObservingChargingStateMode() {
        task = Task {
            for await (chargingMode, manageCharging) in combineLatest(
                appChargingState.observeChargingStateMode(),
                defaults.observe(.manageCharging)
            ) {
                guard chargingMode != .chargerNotConnected
                        && chargingMode != .initial
                        && manageCharging else { continue }
                logger.info("Should display notification")
                await showChargingStateModeDidChangeNotification(chargingMode)
            }
        }
    }

    func cancelObservingChargingStateMode() {
        task?.cancel()
    }

    func showChargingStateModeDidChangeNotification(_ mode: AppChargingMode) async {
        let granted = try? await center.requestAuthorization(options: [.alert, .provisional])
        if granted == true {
            logger.info("permission granted, should dispatch the notification")
            center.removeAllPendingNotificationRequests()

            let content = UNMutableNotificationContent()
            content.subtitle = "New mode: \(mode.stateDescription)"
            let chargeLimitFraction = Double(Defaults[.chargeLimit]) / 100
            if let description = mode.stateDescription(chargeLimitFraction: chargeLimitFraction) {
                content.body = description
            } else {
                content.body = ""
            }

            content.interruptionLevel = .critical // to show the notification
            let uuidString = UUID().uuidString
            let request = UNNotificationRequest(
                identifier: uuidString,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1.5, repeats: false)
            )
            
            do {
                logger.debug("Adding notifications request to the notification center")
                try await center.add(request)
            } catch {
                logger.error("Notifications request error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier == updateNotificationIdentifier
            && response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            // If the notificaton is clicked on, make sure we bring the update in focus
            // If the app is terminated while the notification is clicked on,
            // this will launch the application and perform a new update check.
            // This can be more likely to occur if the notification alert style is Alert rather than Banner
            updater.checkForUpdates()
        }
        completionHandler()
    }
}
