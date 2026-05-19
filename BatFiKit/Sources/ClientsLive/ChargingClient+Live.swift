//
//  ChargingClient.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppKit
import Clients
import Dependencies
import Shared

extension ChargingClient: DependencyKey {
    public static let liveValue: ChargingClient = {
        return Self(
            turnOnAutoChargingMode: {
                try await XPCClient.shared.changeChargingMode(.auto)
            },
            inhibitCharging: {
                try await XPCClient.shared.changeChargingMode(.inhibitCharging)
            },
            forceDischarge: {
                try await XPCClient.shared.changeChargingMode(.forceDischarging)
            },
            restoreSystemDefaults: {
                try await XPCClient.shared.restoreSystemDefaults()
            },
            chargingStatus: {
                return try await XPCClient.shared.getSMCChargingStatus()
            },
            mclStatus: {
                return try await XPCClient.shared.getMCLStatus()
            }
        )
    }()
}
