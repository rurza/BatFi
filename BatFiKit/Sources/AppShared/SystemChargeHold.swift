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
    ///   - chargeIsFlowingIn: the SMC's answer to whether power is going *into* the battery
    ///     (`PowerDistributionInfo.batteryPower < 0`), or **nil where it was not asked** —
    ///     it costs an XPC round trip, so callers that have not paid for one still get the
    ///     IOKit answer rather than nothing.
    ///   - batFiIsDischarging: whether BatFi is running the battery down on the user's own
    ///     instruction (`.forceDischarge`). Has to be told, because the firmware attributes
    ///     that discharge as a hold on purpose — `holdsChargeBack` counts
    ///     `adapterDisabledCH0I`/`CH0J` so a deliberate discharge is not read as a broken
    ///     mechanism — which leaves it indistinguishable from this fault by every other input.
    ///   - mechanismOwnsChargingDecision: `ChargeBackend.dischargesToLimitItself`.
    ///   - enforcedLimit: the `soclimit` powerd is enforcing (`PowerdChargePolicy`), or **nil
    ///     where it was not read or there is none** — nil is "no evidence", and the applied
    ///     limit is judged as before.
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
    ///
    /// **No verdict while powerd has yet to adopt a raised limit** (`isAwaitingAdoption`).
    /// powerd takes up to 45 s to adopt a new limit, and `limitInForce` is what BatFi applied,
    /// so a raise opens a window in which the two disagree. Reported from hardware: an inhibit
    /// frozen at 77% was resumed, 80 applied, and the battery sat at 77% under the old limit,
    /// not charging, the firmware naming that limit as the hold — "Charging paused by macOS",
    /// with a banner, about a battery held *at* the limit still in force. The same window
    /// opens whenever the slider goes up under a battery between the two values.
    ///
    /// Below the old limit too, not only between the two. A hold that was already there
    /// before the raise would otherwise be re-announced with the new limit in its body, and
    /// the raise itself is the change in the enforced value that re-opens the charge session
    /// once powerd adopts it — so "paused" is the one thing that window will not stay.
    public static func isHoldingBelowLimit(
        chargerConnected: Bool,
        isCharging: Bool,
        batteryLevel: Int,
        limitInForce: Int,
        holdIsAttributed: Bool?,
        chargeIsFlowingIn: Bool?,
        batFiIsDischarging: Bool,
        mechanismOwnsChargingDecision: Bool,
        enforcedLimit: Int? = nil
    ) -> Bool {
        guard mechanismOwnsChargingDecision, chargerConnected, !isCharging else { return false }
        // The same exclusion `ChargeHoldDrift`'s caller makes, and needed here for a sharper
        // reason: this fault has a remedy that writes to the charge limit, so mistaking a
        // discharge the user asked for would have BatFi nudging the limit to undo its own work.
        guard !batFiIsDischarging else { return false }
        // The SMC outranks IOKit here, and only in this direction. Measured 2026-08-19: the SMC
        // reported 46.2W going into the battery while `AppleSmartBattery` still said 0 mA, not
        // charging, bit 24 set — and IOKit did not catch up for ~17s. Trusting IOKit alone put
        // "Charging paused by macOS" directly above a graph showing 46W entering the battery.
        //
        // It cannot create a hold, only end one: a `false` from the SMC is not taken as proof of
        // the fault on its own, because a battery merely resting at 0 mA reads the same way.
        if chargeIsFlowingIn == true { return false }
        if isAwaitingAdoption(limitInForce: limitInForce, enforcedLimit: enforcedLimit) { return false }
        return batteryLevel < limitInForce && holdIsAttributed == true
    }

    /// Whether powerd has yet to adopt a limit BatFi raised: it enforces a value below the
    /// one applied.
    ///
    /// The window in which `isHoldingBelowLimit` gives no verdict, and so in which the
    /// charge-resume nudge never counts a stall: the battery is not charging because the old
    /// limit is still doing its job, and a nudge written on top of an adoption in flight is
    /// a second limit change racing the first. Only a raise: powerd above the
    /// applied value is a lowered limit draining down, or an off-step value rounded up, and
    /// neither can be misread as a hold below the limit. No policy is no evidence.
    public static func isAwaitingAdoption(limitInForce: Int, enforcedLimit: Int?) -> Bool {
        guard let enforcedLimit else { return false }
        return enforcedLimit < limitInForce
    }
}
