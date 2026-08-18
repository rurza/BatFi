//
//  AppChargingState.Mode+.swift
//
//
//  Created by Adam on 15/05/2023.
//

import Foundation
import L10n

public extension AppChargingMode {
    /// The state line, told through what the app can actually verify.
    ///
    /// The mode is only ever as good as the helper that reported it, and `.enabled` is not
    /// proof that a helper exists to report anything. A Background Task Management record
    /// registered by a copy of BatFi that has since been deleted, moved, or replaced by
    /// another copy keeps reporting `.enabled` while launchd fails every spawn — so the app
    /// either never gets a first mode and sits on `.initial`, or holds the last mode it saw
    /// before the helper went away. Both are reported here as what they are.
    ///
    /// Only `.degraded` overrides the mode. `.unknown` is the ordinary launch window before
    /// the first probe lands, where "Initializing" is the honest answer.
    func stateDescription(helperHealth: HelperHealth) -> String {
        if case .degraded = helperHealth {
            return L10n.AppChargingMode.State.Title.helperNotRunning
        }
        return stateDescription
    }

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
            // `.inhibit` covers two different things on two different kinds of Mac, and only
            // one of them is BatFi pausing charging. Where the mechanism owns the charging
            // decision, macOS drains the battery down to the limit itself and BatFi writes
            // no inhibit at all — so this is the mode BatFi records for "charge is being
            // held, just not by me", and the label has to say which.
            //
            // The description below is left alone deliberately: "The charging limit is set
            // to 55%" is true either way, and it is the title that a user watching 61% fall
            // toward 55% can prove wrong.
            return systemIsDischargingToLimit ? label.systemDischargingToLimit : label.inhibit
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
