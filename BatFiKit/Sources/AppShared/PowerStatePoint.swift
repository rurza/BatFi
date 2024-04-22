//
//  PowerStatePoint.swift
//
//
//  Created by Adam on 19/08/2023.
//

import Foundation

public struct PowerStatePoint: Identifiable {
    public let batteryLevel: Int16
    public let appChargingMode: AppChargingMode
    public let isCharging: Bool
    public let timestamp: Date
    public let batteryTemperature: Double

    public init(
        batteryLevel: Int16,
        appChargingMode: AppChargingMode,
        isCharging: Bool,
        timestamp: Date,
        batteryTemperature: Double
    ) {
        self.batteryLevel = batteryLevel
        self.appChargingMode = appChargingMode
        self.isCharging = isCharging
        self.timestamp = timestamp
        self.batteryTemperature = batteryTemperature
    }

    public var id: Date { timestamp }
}
