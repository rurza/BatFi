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

        guard mode != .initial else {
            return label.initial
        }

        guard chargerConnected || mode == .forceDischarge else {
            return label.chargerNotConnected
        }

        if userTempOverride != nil {
            return label.chargeOverride
        }

        switch self.mode {
        case .initial:
            return label.initial
        case .charging:
            return label.charging
        case .forceDischarge:
            return label.forceDischarge
        case .inhibit:
            return label.inhibit
        }
    }

    /// - Parameter automationRuleName: When non-nil, the effective limit comes from an active
    ///   automation rule, so the description names it (e.g. "set by automation “Work”").
    ///   A manual temp override takes precedence over automation, so attribution is suppressed
    ///   whenever an override is present.
    func stateDescription(chargeLimitFraction limit: Double, automationRuleName: String? = nil) -> String? {
        let limit = percentageFormatter.string(from: limit as NSNumber)!
        let label = L10n.AppChargingMode.State.Description.self

        guard chargerConnected || mode == .forceDischarge else {
            return nil
        }

        if let overrideLimit = userTempOverride?.limit {
            let limitFraction = Double(overrideLimit) / 100
            let percentage = percentageFormatter.string(from: NSNumber(floatLiteral: limitFraction))!
            return label.tempChargingTo(percentage)
        }

        switch self.mode {
        case .initial:
            return nil
        case .charging:
            if let automationRuleName {
                return L10n.Automation.chargingByAutomation(limit, name: automationRuleName)
            }
            return label.charging(limit)
        case .forceDischarge:
            if let automationRuleName {
                return L10n.Automation.forceDischargeByAutomation(name: automationRuleName)
            }
            return label.forceDischarge
        case .inhibit:
            if let automationRuleName {
                return L10n.Automation.inhibitByAutomation(limit, name: automationRuleName)
            }
            return label.inhibit(limit)
        }
    }
}
