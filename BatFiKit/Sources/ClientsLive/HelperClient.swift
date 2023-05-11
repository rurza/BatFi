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
            turnOnAutoChargingMode: { quitHelper in
                try await xpcClient.sendMessage(
                    SMCChargingCommand.auto,
                    to: XPCRoute.charging
                )
                if quitHelper {
                    try? await xpcClient.send(to: XPCRoute.quit)
                }
            },
            inhibitCharging: { quitHelper in
                try await xpcClient.sendMessage(
                    SMCChargingCommand.inhibitCharging,
                    to: XPCRoute.charging
                )
                if quitHelper {
                    try? await xpcClient.send(to: XPCRoute.quit)
                }
            },
            forceDischarge: { quitHelper in
                try await xpcClient.sendMessage(
                    SMCChargingCommand.forceDischarging,
                    to: XPCRoute.charging
                )
                if quitHelper {
                    try? await xpcClient.send(to: XPCRoute.quit)
                }
            },
            chargingStatus: { quitHelper in
                let status = try await xpcClient.sendMessage(SMCStatusCommand.status, to: XPCRoute.smcStatus)
                if quitHelper {
                    try? await xpcClient.send(to: XPCRoute.quit)
                }
                return status
            },
            quitChargingHelper: {
                try await xpcClient.send(to: XPCRoute.quit)
            }
        )
        return client
    }()
}
