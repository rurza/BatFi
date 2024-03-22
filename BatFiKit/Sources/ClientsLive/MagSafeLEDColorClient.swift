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
import SecureXPC
import Shared

extension MagSafeLEDColorClient: DependencyKey {
    public static var liveValue: MagSafeLEDColorClient = {
        let logger = Logger(category: "🔌🚦")

        func createClient() -> XPCClient {
            XPCClient.forMachService(
                named: Constant.helperBundleIdentifier,
                withServerRequirement: try! .sameTeamIdentifier
            )
        }

        let client = Self(
            changeMagSafeLEDColor: { (option: MagSafeLEDOption) in
                do {
                    return try await createClient().sendMessage(option, to: XPCRoute.magSafeLEDColor)
                } catch {
                    logger.error("Error when chaging the color of MagSafe: \(error.localizedDescription, privacy: .public)")
                    throw error
                }
            }
        )
        return client
    }()
}
