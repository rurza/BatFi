//
//  PowerStateModel+PowerState.swift
//  
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import CoreData
import Foundation

extension PowerStateModel {
    public convenience init(
        powerState: PowerState,
        appMode: AppChargingMode,
        context: NSManagedObjectContext
    ) {
        self.init(context: context)
        self.batteryLevel = Int16(powerState.batteryLevel)
        self.batteryTemperature = powerState.batteryTemperature
        self.chargerConnected = powerState.chargerConnected
        self.isCharging = powerState.isCharging
        self.timestamp = Date.now
        self.appMode = appMode.rawValue
    }

    public var point: PowerStatePoint {
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
