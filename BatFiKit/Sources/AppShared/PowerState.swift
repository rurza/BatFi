//
//  PowerState.swift
//  
//
//  Created by Adam on 28/04/2023.
//

import Foundation

public struct PowerState: CustomStringConvertible, Equatable {

    public let batteryLevel: Int
    public let isCharging: Bool
    public let powerSource: String
    public let timeLeft: Int
    public let timeToCharge: Int
    public let batteryCycleCount: Int
    public let batteryCapacity: Double
    public let batteryTemperature: Double
    public let chargerConnected: Bool
    public let optimizedBatteryChargingEngaged: Bool

    public init(
        batteryLevel: Int,
        isCharging: Bool,
        powerSource: String,
        timeLeft: Int,
        timeToCharge: Int,
        batteryCycleCount: Int,
        batteryCapacity: Double,
        batteryTemperature: Double,
        chargerConnected: Bool,
        optimizedBatteryChargingEngaged: Bool
    ) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.timeLeft = timeLeft
        self.timeToCharge = timeToCharge
        self.batteryCycleCount = batteryCycleCount
        self.batteryCapacity = batteryCapacity
        self.batteryTemperature = batteryTemperature
        self.chargerConnected = chargerConnected
        self.optimizedBatteryChargingEngaged = optimizedBatteryChargingEngaged
    }

    public var description: String {
        """
PowerState |==> is charging: \(isCharging), battery level: \(batteryLevel), power source: \(powerSource), time left: \(timeLeft), time to charge: \(timeToCharge), cycle count: \(batteryCycleCount), battery capacity: \(batteryCapacity), battery temperature: \(batteryTemperature)°C, charger connected: \(chargerConnected), optimized battery charging engaged: \(optimizedBatteryChargingEngaged)
"""
    }
}
