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
        appMode: AppChargingMode,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        batteryLevel = Int16(powerState.batteryLevel)
        batteryTemperature = powerState.batteryTemperature
        chargerConnected = powerState.chargerConnected
        isCharging = powerState.isCharging
        timestamp = Date.now
        self.appMode = appMode.rawValue
    }

    var point: PowerStatePoint {
        PowerStatePoint(
            batteryLevel: batteryLevel,
            appMode: AppChargingMode(rawValue: appMode)!,
            isCharging: isCharging,
            timestamp: timestamp,
            batteryTemperature: batteryTemperature,
            chargerConnected: chargerConnected
        )
    }
}
