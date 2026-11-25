//
//  PowerStateModel+PowerState.swift
//
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import CoreData
import Foundation

public extension PowerStateModel {
    convenience init(
        powerState: PowerState,
        appChargingMode: AppChargingMode,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        batteryLevel = Int16(powerState.batteryLevel)
        // Core Data scalar attribute; temperature is a secondary chart series, so an
        // unknown reading records as 0 rather than dropping the whole sample.
        batteryTemperature = powerState.batteryTemperature ?? 0
        chargerConnected = powerState.chargerConnected
        isCharging = powerState.isCharging
        timestamp = Date.now
        appMode = appChargingMode.mode.rawValue
    }

    var point: PowerStatePoint {
        PowerStatePoint(
            batteryLevel: batteryLevel,
            appChargingMode: AppChargingMode(
                mode: ChargingMode(rawValue: appMode) ?? .initial,
                userTempOverride: nil,
                chargerConnected: chargerConnected
            ),
            isCharging: isCharging,
            timestamp: timestamp,
            batteryTemperature: batteryTemperature
        )
    }
}
