//
//  SMCStatus.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Foundation

struct SMCStatus: Codable, CustomStringConvertible {
    let forceCharging: Bool
    let inhitbitCharging: Bool
    let lidClosed: Bool

    var description: String {
        "force charging: \(forceCharging), inhitbitCharging: \(inhitbitCharging), lidClosed: \(lidClosed))"
    }
}
