//
//  PowerState.swift
//  
//
//  Created by Adam on 28/04/2023.
//

import Foundation

public struct PowerState: CustomStringConvertible {
    public let batteryLevel: Int?
    public let isCharging: Bool?
    public let powerSource: String?
    public let timeLeft: Int?
    public let timeToCharge: Int?
    public let batteryCycleCount: Int?
    public let batteryHealth: Int?
    public let batteryTemperature: Double?

    public var description: String {
        """
PowerState
- is charging: \(isCharging ?? false),
- battery level: \(batteryLevel ?? -1),
- power source: \(powerSource ?? "not known"),
- time left: \(timeLeft.safeDescription)
- time to charge: \(timeToCharge.safeDescription)
- cycle count: \(batteryCycleCount.safeDescription)
- battery health: \(batteryHealth.safeDescription)
- battery temperature: \(batteryTemperature?.description ?? "not known")°C
"""
    }
}

private extension Optional where Wrapped == Int {
    var safeDescription: String {
        switch self {
        case .none:
            return "not known"
        case .some(let value):
            return value.description
        }
    }
}
