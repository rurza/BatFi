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
            // `.inhibit` covers three different things, and only one of them is BatFi pausing
            // charging. Where the mechanism owns the charging decision, macOS drains the
            // battery down to the limit itself and BatFi writes no inhibit at all — so this
            // is the mode BatFi records for "charge is being held, just not by me", and the
            // label has to say which.
            //
            // The order is the precedence, and it is pinned by a test. All three system
            // states are mutually exclusive on any real reading — the top-up and the drain
            // read one direction rule and negate it, and the hold needs the battery below a
            // limit both of the others need it above — but the flags are independent, so an
            // order is still owed.
            //
            // The top-up leads because it is the one whose absence was a contradiction rather
            // than merely a vague label: for as long as the drain was keyed on the level
            // alone, a Mac being charged to 100% by macOS was told it was discharging.
            if systemIsChargingPastLimit {
                return label.systemChargingPastLimit
            }
            if systemIsDischargingToLimit {
                return label.systemDischargingToLimit
            }
            if systemIsHoldingBelowLimit {
                return label.systemHoldingBelowLimit
            }
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
            // Ahead of the automation attribution, and the one place the description does not
            // simply restate the limit. "The charging limit is set to 75%" is true while the
            // battery sits at 100%, and it is the sentence that makes a user read the state
            // as BatFi having failed; naming the rule that set the limit helps even less.
            // Which limit is in force is not in doubt here — that it still applies is.
            if systemIsChargingPastLimit {
                return label.systemChargingPastLimit(limit)
            }
            if let automationRuleName {
                return L10n.Automation.inhibitByAutomation(limit, name: automationRuleName)
            }
            return label.inhibit(limit)
        }
    }
}
