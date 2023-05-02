//
//  BatteryInfo.swift
//  BatFi
//
//  Created by Adam on 19/04/2023.
//

import Foundation

struct BatteryInfo: Codable {
    let batteryPercentage: Int
    let isCharging: Bool
}
