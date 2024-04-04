//
//  ChargingClient.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppKit
import AppShared
import Clients
import Dependencies
import IOKit.pwr_mgt
import os
import Sentry
import Shared

extension ChargingClient: DependencyKey {
    public static let liveValue: ChargingClient = {
        let logger = Logger(category: "Charging Client")

        return Self(
            turnOnAutoChargingMode: {
                do {
                    try await XPCClient.shared.changeChargingMode(.auto)
                } catch {
                    SentrySDK.capture(error: error)
                    logger.log(level: .error, "turnOnAutoChargingMode error: \(error)")
                    throw(error)
                }
            }, 
            inhibitCharging: {
                do {
                    try await XPCClient.shared.changeChargingMode(.inhibitCharging)
                } catch {
                    SentrySDK.capture(error: error)
                    logger.log(level: .error, "inhibitCharging error: \(error)")
                    throw(error)
                }
            }, 
            forceDischarge: {
                do {
                    try await XPCClient.shared.changeChargingMode(.forceDischarging)
                } catch {
                    SentrySDK.capture(error: error)
                    logger.log(level: .error, "forceDischarge error: \(error)")
                    throw(error)
                }
            }, 
            chargingStatus: {
                do {
                    return try await XPCClient.shared.getSMCChargingStatus()
                } catch {
                    SentrySDK.capture(error: error)
                    logger.log(level: .error, "chargingStatus error: \(error)")
                    throw(error)
                }
            }, 
            enableSystemChargeLimit: {
                do {
                    try await XPCClient.shared.changeChargingMode(.enableSystemChargeLimit)
                } catch {
                    SentrySDK.capture(error: error)
                    logger.log(level: .error, "ChargingClient error: \(error)")
                    throw(error)
                }
            }
        )
    }()
}
