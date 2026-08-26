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
    ///   - isCharging: `kIOPSIsChargingKey`, and `batteryPower` the SMC's signed reading. Both
    ///     go to `ChargeDirection`; the SMC is what keeps the first ~17s of a top-up from
    ///     reading as something else while IOKit catches up.
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
    ///
    /// **Two readings, one episode.** Charge arriving is the climb. A battery resting at *full*
    /// above the limit is the same episode after the charge has finished and before macOS gives
    /// the limit back — measured 2026-08-26 sitting there for hours with `Amperage` 0,
    /// `FullyCharged` true and `NotChargingReason` naming `batteryFull` rather than the charge
    /// limit. Reporting only the climb left the plateau to be read as a drain by one rule and as
    /// a limit that had stopped holding by another, on the same pass.
    ///
    /// **At full the level decides and the reading is not consulted.** That is a stability
    /// requirement, not a shortcut. A full battery on the charger sits near zero and jitters,
    /// and it briefly supplements the adapter whenever a load burst outruns it: measured
    /// 2026-08-26 crossing a 0.1 W threshold nine times in four minutes, across 90 successful
    /// SMC reads. Every crossing flipped this state, and every flip fired a "New mode"
    /// notification, so the user was flooded. At full there is nothing an instantaneous reading
    /// can add — a battery at 100% above the user's limit is macOS's doing whichever way a few
    /// tenths of a watt are moving — so every sign gives the same answer and the state cannot
    /// flap.
    ///
    /// The cost, stated so it is a decision rather than an oversight: a drain that has begun but
    /// has not yet moved the level off 100 is reported as the plateau, and gets its own label
    /// the moment the battery reads 99. A late label beats one that oscillates.
    ///
    /// Below full the reading governs again, because there the two states really are different
    /// things and a drain there runs at several watts. Between the limit and full a resting
    /// battery is claimed by neither: no calibration charge ran to 100%, so there is no episode
    /// to attribute a rest to.
    public static func isUnderway(
        batteryLevel: Int,
        limitInForce: Int,
        isCharging: Bool,
        batteryPower: Float?,
        mechanismDrainsToLimitItself: Bool
    ) -> Bool {
        guard mechanismDrainsToLimitItself, batteryLevel > limitInForce else { return false }
        guard batteryLevel < 100 else { return true }
        return ChargeDirection.flow(isCharging: isCharging, batteryPower: batteryPower) == .intoTheBattery
    }
}
