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
import UserNotifications

public class NotificationsManager: NSObject {
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.updater) private var updater
    private lazy var center = UNUserNotificationCenter.current()

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

    private var task: Task<Void, Never>?

    func startObservingChargingStateMode() {
        task = Task {
            for await chargingMode in appChargingState.observeChargingStateMode()
                .debounce(for: .seconds(1), clock: AnyClock(self.clock)) {
                guard chargingMode != .chargerNotConnected
                        && chargingMode != .initial else { return }
                await showChargingStateModeDidChangeNotification(chargingMode)
            }
        }
    }

    func cancelObservingChargingStateMode() {
        task?.cancel()
    }

    func showChargingStateModeDidChangeNotification(_ mode: AppChargingMode) async {
        let granted = try? await center.requestAuthorization(options: [.alert])
        if granted == true {
            center.removeAllPendingNotificationRequests()

            let content = UNMutableNotificationContent()
            content.subtitle = "New mode: \(mode.stateDescription)"
            let chargeLimitFraction = Double(Defaults[.chargeLimit]) / 100
            if let description = mode.stateDescription(chargeLimitFraction: chargeLimitFraction) {
                content.body = description
            }

            content.interruptionLevel = .active // to show the notification
            let uuidString = UUID().uuidString
            let request = UNNotificationRequest(
                identifier: uuidString,
                content: content,
                trigger: nil
            )

            try? await center.add(request)
        }
    }
}

extension NotificationsManager: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner]
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
