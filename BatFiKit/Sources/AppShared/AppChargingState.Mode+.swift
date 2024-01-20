//
//  AppChargingState.Mode+.swift
//
//
//  Created by Adam on 15/05/2023.
//

import Foundation
import L10n

public extension AppChargingMode {
    var stateDescription: String {
        let label = L10n.AppChargingMode.State.Title.self
        switch self {
        case .initial:
            return label.initial
        case .charging:
            return label.charging
        case .forceCharge:
            return label.forceCharge
        case .forceDischarge:
            return label.forceDischarge
        case .inhibit:
            return label.inhibit
        case .chargerNotConnected:
            return label.chargerNotConnected
        }
    }

    func stateDescription(chargeLimitFraction limit: Double) -> String? {
        let limit = percentageFormatter.string(from: limit as NSNumber)!
        let label = L10n.AppChargingMode.State.Description.self

        switch self {
        case .initial:
            return nil
        case .charging:
            return label.charging(limit)
        case .forceCharge:
            return label.forceCharge
        case .forceDischarge:
            return label.forceDischarge
        case .inhibit:
            return label.inhibit(limit)
        case .chargerNotConnected:
            return nil
        }
    }
}
