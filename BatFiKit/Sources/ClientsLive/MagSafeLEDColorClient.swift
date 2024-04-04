//
//  MagSafeLEDColorClient.swift
//
//
//  Created by Adam on 16/07/2023.
//

import Clients
import Dependencies
import Foundation
import os
import Sentry
import Shared

extension MagSafeLEDColorClient: DependencyKey {
    public static var liveValue: MagSafeLEDColorClient = {
        let logger = Logger(category: "MagSafe color")

        let client = Self(
            changeMagSafeLEDColor: { (option: MagSafeLEDOption) in
                do {
                    return try await XPCClient.shared.changeMagSafeLEDColor(option)
                } catch {
                    SentrySDK.capture(error: error)
                    logger.error("Error when chaging the color of MagSafe: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
        )
        return client
    }()
}
