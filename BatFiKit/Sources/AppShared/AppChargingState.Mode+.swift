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
        case .initial:
            return "Initializing"
        case .charging:
            return "Charging to the limit"
        case .disabled:
            return "Disabled"
        case .forceCharge:
            return "Charging"
        case .forceDischarge:
            return "Discharging"
        case .inhibit:
            return "Inhibiting charging"
        case .chargerNotConnected:
            return "Charger not connected"
        }
    }

    func stateDescription(chargeLimitFraction limit: Double) -> String? {
        let limit = percentageFormatter.string(from: limit as NSNumber)!
        switch self {
        case .initial:
            return nil
        case .charging:
            return "The limit is \(limit)."
        case .disabled:
            return "Automatically manage charging is turned off."
        case .forceCharge:
            return "Charging to 100%."
        case .forceDischarge:
            return "Using the battery."
        case .inhibit:
            return "The charging limit is set to \(limit)."
        case .chargerNotConnected:
            return nil
        }
    }


}
