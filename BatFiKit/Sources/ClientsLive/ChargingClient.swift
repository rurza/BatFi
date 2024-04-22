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
            chargingStatus: {
                return try await XPCClient.shared.getSMCChargingStatus()
            }, 
            enableSystemChargeLimit: {
                try await XPCClient.shared.changeChargingMode(.enableSystemChargeLimit)
            }
        )
    }()
}
