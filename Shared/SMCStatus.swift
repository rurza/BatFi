//
//  SMCStatus.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Foundation

struct SMCStatus: Codable {
    let forceCharging: Bool
    let inhitbitCharging: Bool
    let lidClosed: Bool
    let batteryTemperature: Double?
}
