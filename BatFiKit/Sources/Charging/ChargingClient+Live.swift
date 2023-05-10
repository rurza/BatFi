//
//  ChargingClient+Live.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Cocoa
import Dependencies
import IOKit.pwr_mgt
import os
import SecureXPC
import Shared

extension ChargingClient: DependencyKey {
    public static var liveValue: ChargingClient = {
        let logger = Logger(category: "🪫🔋")
        let xpcClient = XPCClient.forMachService(
            named: Constant.helperBundleIdentifier,
            withServerRequirement: try! .sameTeamIdentifier
        )
        let client = ChargingClient(
            turnOnAutoChargingMode: {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.auto,
                    to: XPCRoute.charging
                )
                try? await xpcClient.send(to: XPCRoute.quit)
            },
            inhibitCharging: {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.inhibitCharging,
                    to: XPCRoute.charging
                )
                try? await xpcClient.send(to: XPCRoute.quit)
            },
            forceDischarge: {
                try await xpcClient.sendMessage(
                    SMCChargingCommand.forceDischarging,
                    to: XPCRoute.charging
                )
                try? await xpcClient.send(to: XPCRoute.quit)
            },
            chargingStatus: {
                let status = try await xpcClient.sendMessage(SMCStatusCommand.status, to: XPCRoute.smcStatus)
                try? await xpcClient.send(to: XPCRoute.quit)
                return status
            }
        )
        return client
    }()
}

extension DependencyValues {
    public var chargingClient: ChargingClient {
        get { self[ChargingClient.self] }
        set { self[ChargingClient.self] = newValue }
    }
}
