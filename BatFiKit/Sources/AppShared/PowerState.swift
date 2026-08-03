//
//  PowerState.swift
//
//
//  Created by Adam on 28/04/2023.
//

import Foundation

public struct PowerState: CustomStringConvertible, Equatable, Sendable {
    public let batteryLevel: Int
    public let isCharging: Bool
    public let powerSource: String
    public let timeLeft: Int?
    public let timeToCharge: Int?
    public let batteryCycleCount: Int?
    public let batteryHealth: Int?
    public let batteryTemperature: Double?
    public let chargerConnected: Bool
    public let optimizedBatteryChargingEngaged: Bool?

    public init(
        batteryLevel: Int,
        isCharging: Bool,
        powerSource: String,
        timeLeft: Int?,
        timeToCharge: Int?,
        batteryCycleCount: Int?,
        batteryHealth: Int?,
        batteryTemperature: Double?,
        chargerConnected: Bool,
        optimizedBatteryChargingEngaged: Bool?
    ) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.timeLeft = timeLeft
        self.timeToCharge = timeToCharge
        self.batteryCycleCount = batteryCycleCount
        self.batteryHealth = batteryHealth
        self.batteryTemperature = batteryTemperature
        self.chargerConnected = chargerConnected
        self.optimizedBatteryChargingEngaged = optimizedBatteryChargingEngaged
    }

    public var description: String {
        """
        PowerState |==> is charging: \(isCharging), battery level: \(batteryLevel), power source: \(powerSource), time left: \(timeLeft?.description ?? "unknown"), time to charge: \(timeToCharge?.description ?? "unknown"), cycle count: \(batteryCycleCount?.description ?? "unknown"), battery health: \(batteryHealth?.description ?? "unknown"), battery temperature: \(batteryTemperature?.description ?? "unknown")°C, charger connected: \(chargerConnected), optimized battery charging engaged: \(String(describing: optimizedBatteryChargingEngaged))
        """
    }
}
