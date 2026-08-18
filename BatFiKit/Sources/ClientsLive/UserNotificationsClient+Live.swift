//
//  UserNotificationsClient.swift
//
//
//  Created by Adam Różyński on 27/03/2024.
//

import Clients
import Dependencies
import DependenciesMacros
import Foundation
import os
import Shared
import UserNotifications

extension UserNotificationsClient: DependencyKey {
    nonisolated(unsafe) public static var liveValue: UserNotificationsClient = {
        nonisolated(unsafe) let center = UNUserNotificationCenter.current()
        let logger = Logger(category: "User Notifications Client")

        return UserNotificationsClient(
            requestAuthorization: {
                try? await center.requestAuthorization(options: [.alert, .sound])
            },
            showUserNotification: { title, body, identifier, threadIdentifier, delay in
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                if let threadIdentifier {
                    content.threadIdentifier = threadIdentifier
                }

                let trigger: UNTimeIntervalNotificationTrigger?
                if let delay {
                    trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                } else {
                    trigger = nil
                }

                content.interruptionLevel = .active // to show the notification
                // Unique per notification, with the caller's identifier kept as the prefix so
                // the logs stay readable.
                //
                // A reused identifier makes the new notification *replace* the delivered one
                // rather than arrive as a new one, and a replacement updates the entry in
                // Notification Center instead of presenting a banner. These report in-app
                // events — a charging mode change, a power mode change, a battery warning —
                // where each occurrence is its own event and has to be able to announce
                // itself. `threadIdentifier` is what groups them, and it is passed separately.
                //
                // Nothing reads these back: the one identifier the app matches on afterwards
                // belongs to the update notification, which `Updater+Live` posts to the centre
                // directly rather than through here.
                let request = UNNotificationRequest(
                    identifier: "\(identifier).\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )

                try await center.add(request)
            }
        )
    }()
}


