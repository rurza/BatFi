//
//  PowerStatePoint.swift
//
//
//  Created by Adam on 19/08/2023.
//

import Foundation

public struct PowerStatePoint: Identifiable {
    public let batteryLevel: Int16
    public let appMode: AppChargingMode
    public let isCharging: Bool
    public let timestamp: Date
    public let batteryTemperature: Double
    public let chargerConnected: Bool

    public init(
        batteryLevel: Int16,
        appMode: AppChargingMode,
        isCharging: Bool,
        timestamp: Date,
        batteryTemperature: Double,
        chargerConnected: Bool
    ) {
        self.batteryLevel = batteryLevel
        self.appMode = appMode
        self.isCharging = isCharging
        self.timestamp = timestamp
        self.batteryTemperature = batteryTemperature
        self.chargerConnected = chargerConnected
    }

    public var id: Date { timestamp }
}
