//
//  NotificationsManager.swift
//  
//
//  Created by Adam on 17/05/2023.
//

import AppShared
import Foundation
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import UserNotifications

public class NotificationsManager: NSObject {
    @Dependency(\.appChargingState) private var appChargingState
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
            for await chargingMode in appChargingState.observeChargingStateMode() {
                await showChargingStateModeDidChangeNotification(chargingMode)
            }
        }
    }

    func cancelObservingChargingStateMode() {
        task?.cancel()
    }

    func showChargingStateModeDidChangeNotification(_ mode: AppChargingMode) async {
        let granted = try? await center.requestAuthorization(options: [.alert, .providesAppNotificationSettings])
        if granted == true {
            center.removeAllPendingNotificationRequests()

            let content = UNMutableNotificationContent()
            content.title = "The charging mode has changed"

            content.body = mode.stateDescription(Defaults[.chargeLimit] / 100)

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
}
