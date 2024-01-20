//
//  SleepClient.swift
//
//
//  Created by Adam on 11/05/2023.
//

import AsyncAlgorithms
import Clients
import Cocoa
import Dependencies
import os
import Shared

extension SleepClient: DependencyKey {
    public static let liveValue: SleepClient = {
        let logger = Logger(category: "😴")
        func asyncStreamForNotificationName(_ notificationName: Notification.Name) -> AsyncStream<Void> {
            AsyncStream(
                NSWorkspace
                    .shared
                    .notificationCenter
                    .notifications(named: notificationName)
                    .map { _ in
                        logger.debug("received notification for \(notificationName.rawValue)")
                    }
            )
        }

        let client = SleepClient(
            macWillSleep: {
                asyncStreamForNotificationName(NSWorkspace.willSleepNotification)
            },
            macDidWake: {
                asyncStreamForNotificationName(NSWorkspace.didWakeNotification)
            },
            screenDidSleep: {
                asyncStreamForNotificationName(NSWorkspace.screensDidSleepNotification)
            },
            screenDidWake: {
                asyncStreamForNotificationName(NSWorkspace.screensDidWakeNotification)
            },
            observeMacSleepStatus: {
                AsyncStream(
                    merge(
                        asyncStreamForNotificationName(NSWorkspace.willSleepNotification).map { _ in SleepNotification.willSleep },
                        asyncStreamForNotificationName(NSWorkspace.didWakeNotification).map { _ in SleepNotification.didWake }
                    )
                )
            }
        )
        return client
    }()
}
