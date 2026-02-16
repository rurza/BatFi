//
//  ScreenParametersClient.swift
//
//
//  Created by Adam on 04/05/2023.
//

import Clients
import Cocoa
import Dependencies
import os
import Shared

extension ScreenParametersClient: DependencyKey {
    public static let liveValue: ScreenParametersClient = {
        let logger = Logger(category: "📺")
        let screenCounter = ScreenCounter()
        let client = ScreenParametersClient(
            screenDidChangeParameters: {
                AsyncStream { continuation in
                    let task = Task {
                        for await note in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                            let currentCount = await MainActor.run { NSScreen.screens.count }
                            let previousCount = await screenCounter.count
                            if currentCount != previousCount {
                                await screenCounter.setCount(currentCount)
                                logger.debug("\(NSApplication.didChangeScreenParametersNotification.rawValue)")
                                continuation.yield()
                            }
                        }
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            }
        )
        return client
    }()
}

private actor ScreenCounter {
    var count: Int = NSScreen.screens.count

    func setCount(_ newCount: Int) {
        count = newCount
    }
}
