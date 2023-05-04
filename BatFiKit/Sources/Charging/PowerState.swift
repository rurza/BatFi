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

    public var description: String {
        """
PowerState
- is charging: \(isCharging ?? false),
- battery level: \(batteryLevel ?? -1),
- power source: \(powerSource ?? "not known"),
- time left: \(timeLeft?.description ?? "not known")
- time to charge: \(timeToCharge?.description ?? "not known")
"""
    }
}
