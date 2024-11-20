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
    public static var liveValue: UserNotificationsClient = {
        let center = UNUserNotificationCenter.current()
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
                let request = UNNotificationRequest(
                    identifier: identifier,
                    content: content,
                    trigger: trigger
                )

                try await center.add(request)
            }
        )
    }()
}


