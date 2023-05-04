//
//  ScreenParametersClient+Live.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import Dependencies
import Cocoa

extension ScreenParametersClient: DependencyKey {
    static var liveValue: ScreenParametersClient = {
        let client = ScreenParametersClient(
            screenDidChangeParameters: {
                AsyncStream(
                    NotificationCenter
                        .default
                        .publisher(
                            for: NSApplication.didChangeScreenParametersNotification
                        )
                        .map { _ -> Void in }
                        .values
                )
            }
        )
        return client
    }()
}

extension DependencyValues {
    var screenParametersClient: ScreenParametersClient {
        get { self[ScreenParametersClient.self] }
        set { self[ScreenParametersClient.self] = newValue }
    }
}
