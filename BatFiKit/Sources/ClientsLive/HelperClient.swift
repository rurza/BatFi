//
//  HelperClient+Live.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Clients
import Cocoa
import Dependencies
import IOKit.pwr_mgt
import os
import SecureXPC
import Shared

extension HelperClient: DependencyKey {
    public static var liveValue: HelperClient = {
        let logger = Logger(category: "🪫🔋")
        let xpcClient = XPCClient.forMachService(
            named: Constant.helperBundleIdentifier,
            withServerRequirement: try! .sameTeamIdentifier
        )
        let client = HelperClient(
            turnOnAutoChargingMode: {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.auto,
                    to: XPCRoute.charging
                )
            },
            inhibitCharging: {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.inhibitCharging,
                    to: XPCRoute.charging
                )
            },
            forceDischarge: {
                return try await xpcClient.sendMessage(
                    SMCChargingCommand.forceDischarging,
                    to: XPCRoute.charging
                )
            },
            chargingStatus: {
                return try await xpcClient.sendMessage(SMCStatusCommand.status, to: XPCRoute.smcStatus)
            },
            quitChargingHelper: {
                try await xpcClient.send(to: XPCRoute.quit)
            }
        )
        return client
    }()
}
