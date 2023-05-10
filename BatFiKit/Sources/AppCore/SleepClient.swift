//
//  SleepClient.swift
//  
//
//  Created by Adam on 08/05/2023.
//

import Cocoa
import Dependencies
import os
import Shared

struct SleepClient {
    var macWillSleep: () -> AsyncStream<Void>
    var macDidWake: () -> AsyncStream<Void>
    var screenDidSleep: () -> AsyncStream<Void>
    var screenDidWake: () -> AsyncStream<Void>
}

extension SleepClient: DependencyKey {
    static let liveValue: SleepClient = {
        let logger = Logger(category: "😴")
        func asyncStreamForNotificationName(_ notificationName: Notification.Name) -> AsyncStream<Void> {
            AsyncStream(
                NSWorkspace
                    .shared
                    .notificationCenter
                    .notifications(named: notificationName)
                    .map { _ in
                        NSLog("received notification for \(notificationName.rawValue)")
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
            }
        )
        return client
    }()
}

extension DependencyValues {
    var sleepClient: SleepClient {
        get { self[SleepClient.self] }
        set { self[SleepClient.self] = newValue }
    }
}
