//
//  SystemChargeTopUp.swift
//
//
//  Whether macOS is charging the battery *past* the limit, on its own.
//
//  The third thing `.inhibit` covers on a mechanism that owns the charging decision, and
//  the last one to get a name. Apple documents it: a Mac on Optimised Battery Charging or
//  Charge Limit "will occasionally charge to 100% to maintain accurate battery
//  state-of-charge estimates". BatFi's limit stays in force throughout and macOS overrides
//  it — so, like the drain and the hold, this is a state BatFi did not ask for, issues no
//  write during, and cannot stop.
//
//  Settings has said so since `ChargeControlDisclosure.mayChargeToFullForCalibration`
//  landed. The menu never had a way to, and it is the surface a user actually looks at when
//  the number goes past the one they set: with `SystemChargeDrain` keyed on the level alone,
//  the only label available for a battery above the limit was the drain's, so BatFi reported
//  a top-up as a discharge and drew the status item without its bolt.
//
//  Deliberately says nothing about *why*. From outside, a calibration charge and a limit
//  that stopped being enforced are indistinguishable — the same reading produces both — so
//  naming calibration here would be a confident lie in the failure case. This states what
//  the battery is doing; `ChargeHoldDrift` keeps the separate job of deciding whether it is
//  a fault worth warning about.
//

import Foundation

public enum SystemChargeTopUp {
    /// Whether the top-up is happening right now.
    ///
    /// - Parameters:
    ///   - batteryLevel: the current charge percentage.
    ///   - limitInForce: the limit the mechanism is actually holding, **not** the one the
    ///     user asked for. The two come apart under Apple's Manual Charge Limit, and it is
    ///     the value in force that the battery is climbing past.
    ///   - isCharging: `kIOPSIsChargingKey`, and `chargeIsFlowingIn` the SMC's answer to the
    ///     same question. Both go to `ChargeDirection`; the SMC is what keeps the first ~17s
    ///     of a top-up from reading as a drain while IOKit catches up.
    ///   - mechanismDrainsToLimitItself: `ChargeBackend.dischargesToLimitItself`. False on
    ///     every backend BatFi holds charge on with an inhibit of its own — there, charging
    ///     past the limit is not macOS overriding BatFi but the limit failing, which is
    ///     `ChargeHoldDrift`'s to report and not a state to give a calm label to.
    ///
    /// Strictly above the limit, matching `SystemChargeDrain` and for a sharper reason: an
    /// ordinary charge that has just *reached* the limit still reads as charging at exactly
    /// the limit for as long as IOKit takes to notice it stopped, and calling that a charge
    /// past the limit would relabel every healthy Mac at the moment it finishes charging.
    /// The cost is that the label is the plain inhibit for the one percentage point before
    /// the battery clears the limit.
    public static func isUnderway(
        batteryLevel: Int,
        limitInForce: Int,
        isCharging: Bool,
        chargeIsFlowingIn: Bool?,
        mechanismDrainsToLimitItself: Bool
    ) -> Bool {
        guard mechanismDrainsToLimitItself, batteryLevel > limitInForce else { return false }
        return ChargeDirection.isFlowingIn(isCharging: isCharging, chargeIsFlowingIn: chargeIsFlowingIn)
    }
}
