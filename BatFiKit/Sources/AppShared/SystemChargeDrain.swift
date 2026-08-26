//
//  SystemChargeDrain.swift
//
//
//  Whether macOS is draining the battery down to the limit on its own.
//
//  A fact about the machine, not a command BatFi issues — which is why it is not a
//  `ChargingMode`. Under Apple's Manual Charge Limit the `ChargeCtrlPolicy` powerd
//  registers carries `drain: true`, and the system performs the discharge itself,
//  including with the lid closed and while asleep. It is exposed only behind an
//  Apple-private entitlement, so BatFi can neither ask for it nor stop it.
//
//  Here for the reason `TempOverrideDisconnectPolicy` is here: `AppCore` has no test
//  target, and the boundaries below are exactly the sort of off-by-one that leaves a stale
//  sentence on screen with a green suite. `AppShared` cannot see `ChargeBackend`, so the
//  mechanism's answer arrives as a `Bool` rather than as a backend to re-interrogate.
//

import Foundation

public enum SystemChargeDrain {
    /// Whether the drain is happening right now.
    ///
    /// - Parameters:
    ///   - batteryLevel: the current charge percentage.
    ///   - limitInForce: the limit the mechanism is actually holding — **not** the one the
    ///     user asked for. The two come apart under Apple's Manual Charge Limit, and the
    ///     system drains to the value in force.
    ///   - isCharging: `kIOPSIsChargingKey`, and `batteryPower` the SMC's signed reading. Both
    ///     go to `ChargeDirection`; see there for why two are needed and which wins.
    ///   - mechanismDrainsToLimitItself: `ChargeBackend.dischargesToLimitItself`.
    ///
    /// Strictly above the limit, never at it. At the limit the drain has finished and the
    /// mechanism is holding — the mode is `.inhibit` either way and the mechanism still
    /// drains, so the level is the only thing that separates the two. `>=` here would leave
    /// "Discharging to the limit" on a battery that had stopped discharging, for as long as
    /// it sat there.
    ///
    /// And strictly *charge leaving the battery*. Above the limit on the charger is **three**
    /// states, not one, and the level tells none of them apart:
    ///
    /// - macOS charging past the limit, for the calibration Apple documents — `SystemChargeTopUp`.
    /// - macOS draining back down to the limit — this.
    /// - The battery sitting there, full or held, with nothing flowing at all.
    ///
    /// Both of the first two have been reported as this one. First the top-up, while the level
    /// was the only test: measured 2026-08-26 at 100% against a 75% limit with 477 mA going in.
    /// Then the resting battery, once the test became "charge is not flowing in" — which a
    /// battery at exactly 0 mA also satisfies: measured the same afternoon at 100%, `Amperage`
    /// 0, `FullyCharged` true, 8.2 W going straight past the battery to the system, with
    /// `ChargeHoldDrift` logging every 60s that the limit was not holding while the menu
    /// announced a discharge.
    ///
    /// So this asks for the drain's own direction rather than for the absence of the other's.
    /// A reading that is neither is claimed by neither.
    public static func isUnderway(
        batteryLevel: Int,
        limitInForce: Int,
        isCharging: Bool,
        batteryPower: Float?,
        mechanismDrainsToLimitItself: Bool
    ) -> Bool {
        guard mechanismDrainsToLimitItself, batteryLevel > limitInForce else { return false }
        return ChargeDirection.flow(isCharging: isCharging, batteryPower: batteryPower) == .outOfTheBattery
    }
}
