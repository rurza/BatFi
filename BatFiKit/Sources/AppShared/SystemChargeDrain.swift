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
//  target, and the boundary below is exactly the sort of off-by-one that leaves a stale
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
    ///   - mechanismDrainsToLimitItself: `ChargeBackend.dischargesToLimitItself`.
    ///
    /// Strictly above the limit, never at it. At the limit the drain has finished and the
    /// mechanism is holding — the mode is `.inhibit` either way and the mechanism still
    /// drains, so the level is the only thing that separates the two. `>=` here would leave
    /// "Discharging to the limit" on a battery that had stopped discharging, for as long as
    /// it sat there.
    public static func isUnderway(
        batteryLevel: Int,
        limitInForce: Int,
        mechanismDrainsToLimitItself: Bool
    ) -> Bool {
        mechanismDrainsToLimitItself && batteryLevel > limitInForce
    }
}
