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
    public let batteryHealth: String
    public let batteryTemperature: Double

    public var description: String {
        """
PowerState
- is charging: \(isCharging),
- battery level: \(batteryLevel),
- power source: \(powerSource),
- time left: \(timeLeft)
- time to charge: \(timeToCharge)
- cycle count: \(batteryCycleCount)
- battery health: \(batteryHealth)
- battery temperature: \(batteryTemperature)°C
"""
    }
}
