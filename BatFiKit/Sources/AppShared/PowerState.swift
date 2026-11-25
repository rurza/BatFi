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
    /// Whether `chargerConnected` came from the power-source string rather than from
    /// `ExternalConnected`.
    ///
    /// Carried because the derivation has one known-wrong case and it is the one that
    /// matters: while BatFi force-discharges, the adapter is isolated and IOPS reports
    /// "Battery Power" with the charger plugged in. `ChargerConnection.isConnected` is
    /// where that is dealt with; nothing should read this field on its own.
    public let chargerConnectionIsDerived: Bool
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
        chargerConnectionIsDerived: Bool = false,
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
        self.chargerConnectionIsDerived = chargerConnectionIsDerived
        self.optimizedBatteryChargingEngaged = optimizedBatteryChargingEngaged
    }

    public var description: String {
        """
        PowerState |==> is charging: \(isCharging), battery level: \(batteryLevel), power source: \(powerSource), time left: \(timeLeft?.description ?? "unknown"), time to charge: \(timeToCharge?.description ?? "unknown"), cycle count: \(batteryCycleCount?.description ?? "unknown"), battery health: \(batteryHealth?.description ?? "unknown"), battery temperature: \(batteryTemperature?.description ?? "unknown")°C, charger connected: \(chargerConnected), optimized battery charging engaged: \(String(describing: optimizedBatteryChargingEngaged))
        """
    }
}
