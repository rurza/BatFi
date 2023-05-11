//
//  ScreenParametersClient+Live.swift
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
    public static var liveValue: ScreenParametersClient = {
        let logger = Logger(category: "📺")
        let client = ScreenParametersClient(
            screenDidChangeParameters: {
                AsyncStream(
                    NotificationCenter
                        .default
                        .notifications(named: NSApplication.didChangeScreenParametersNotification)
                        .map { note -> Void in
                            logger.debug("\(note.userInfo?.description ?? "no userInfo", privacy: .public)")
                            logger.debug("\(NSApplication.didChangeScreenParametersNotification.rawValue)")
                        }
                )
            }
        )
        return client
    }()
}
