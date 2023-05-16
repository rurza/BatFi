//
//  AppChargingState.Mode+.swift
//  
//
//  Created by Adam on 15/05/2023.
//

import AppShared

extension AppChargingMode {
    var stateDescription: String {
        switch self {
        case .charging:
            return "Charging to the limit."
        case .disabled:
            return "Automatically manage charging is turned off."
        case .forceCharge:
            return "Charging to 100%."
        case .forceDischarge:
            return "Discharging the battery to the charging limit."
        case .inhibit:
            return "The charging limit reached — inhibiting charging."
        }
    }
}
