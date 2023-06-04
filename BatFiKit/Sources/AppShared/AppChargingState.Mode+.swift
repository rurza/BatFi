//
//  AppChargingState.Mode+.swift
//  
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public extension AppChargingMode {
    var stateDescription: String {
        switch self {
        case .charging:
            return "Charging to the limit."
        case .disabled:
            return "Automatically manage charging is turned off."
        case .forceCharge:
            return "Charging to 100%."
        case .forceDischarge:
            return "Discharging the battery to the charging limit or the charger is not connected."
        case .inhibit:
            return "The charging limit reached — inhibiting charging."
        case .chargerNotConnected:
            return "Charger not connected."
        }
    }

    func stateDescription(_ limit: Double) -> String {
        let limit = percentageFormatter.string(from: limit as NSNumber)!
        switch self {
        case .charging:
            return "Charging to the \(limit)."
        case .disabled:
            return "Automatically manage charging is turned off."
        case .forceCharge:
            return "Charging to 100%."
        case .forceDischarge:
            return "Using the battery."
        case .inhibit:
            return "The charging limit of \(limit) reached — inhibiting charging."
        case .chargerNotConnected:
            return "Charger not connected."
        }
    }


}
