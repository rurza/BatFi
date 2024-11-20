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
        var numberOfScreens = NSScreen.screens.count
        let client = ScreenParametersClient(
            screenDidChangeParameters: {
                NotificationCenter
                    .default
                    .notifications(named: NSApplication.didChangeScreenParametersNotification)
                    .filter { _ in
                        numberOfScreens != NSScreen.screens.count
                    }
                    .map { _ in
                        numberOfScreens = NSScreen.screens.count
                        logger.debug("\(NSApplication.didChangeScreenParametersNotification.rawValue)")
                    }
                    .eraseToStream()
            }
        )
        return client
    }()
}
