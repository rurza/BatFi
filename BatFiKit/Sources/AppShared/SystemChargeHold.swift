//
//  SystemChargeHold.swift
//
//
//  Whether macOS is holding charge on a battery that sits *below* the limit.
//
//  The counterpart to `SystemChargeDrain`, and the other half of what `.inhibit` covers on a
//  mechanism that owns the charging decision. Measured on 26A5416b, 2026-08-19: with 60% in
//  force the battery sat at 56% on mains for two hours at exactly 0 mA, `CHNC` bit 24 set
//  throughout. macOS had drained to the limit, closed the charge session (powerd logs
//  `State: Charging Completed Limited`), and a load heavier than the adapter then pulled the
//  battery below the limit — after which nothing re-opened the session. Re-writing the same
//  limit does not re-open it either; only a *change* in the enforced value does, which is
//  why this is a state to report rather than one BatFi can currently write its way out of.
//
//  It exists because the mode decision reads `batteryLevel < limitInForce` and treats
//  everything below the limit as charging. That holds on every backend BatFi drives with an
//  inhibit of its own, and is false here: the helper writes nothing ("Charging mode is
//  governed by the system charge limit; no SMC write needed") while the firmware holds at
//  0 mA, so the menu read "Charging to the limit" for two hours with no current flowing.
//
//  In `AppShared` for the reason `SystemChargeDrain` is: `AppCore` has no test target, and
//  the boundary against that rule is exactly the sort of off-by-one that leaves a stale
//  sentence on screen with a green suite.
//

import Foundation

public enum SystemChargeHold {
    /// Whether charge is being held right now on a battery below its limit.
    ///
    /// - Parameters:
    ///   - chargerConnected: asked explicitly rather than inferred from the attribution, so
    ///     that a stale `CHNC` read cannot turn an unplugged Mac into a fault.
    ///   - isCharging: `kIOPSIsChargingKey` — current actually flowing **into** the battery.
    ///   - batteryLevel: the current charge percentage.
    ///   - limitInForce: the limit the mechanism is actually holding, **not** the one the
    ///     user asked for. The two come apart under Apple's Manual Charge Limit, and it is
    ///     the value in force that the firmware compares against.
    ///   - holdIsAttributed: whether the firmware names something holding charge back right
    ///     now — `CHNC` bit 24 for Apple's limit. **Nil where it was not asked**, and nil is
    ///     "no evidence", never "nothing is holding".
    ///   - mechanismOwnsChargingDecision: `ChargeBackend.dischargesToLimitItself`.
    ///
    /// Strictly below the limit, never at it. At the limit a mechanism holding charge is
    /// doing exactly what it was asked, and it is already `.inhibit` without this rule —
    /// `<=` here would relabel every healthy Mac that has reached its limit. Above it the
    /// battery belongs to `SystemChargeDrain`, so the two can never both claim one reading.
    ///
    /// The attribution is what separates this from an adapter that cannot keep up: under a
    /// load heavier than the charger the battery also sits below the limit not charging, and
    /// that is not the mechanism's doing. Requiring the firmware to name its own limit keeps
    /// the two apart, and means this answers false on the backends that have no attribution
    /// bit at all rather than guessing.
    public static func isHoldingBelowLimit(
        chargerConnected: Bool,
        isCharging: Bool,
        batteryLevel: Int,
        limitInForce: Int,
        holdIsAttributed: Bool?,
        mechanismOwnsChargingDecision: Bool
    ) -> Bool {
        guard mechanismOwnsChargingDecision, chargerConnected, !isCharging else { return false }
        return batteryLevel < limitInForce && holdIsAttributed == true
    }
}
