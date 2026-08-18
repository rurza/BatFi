//
//  StatusMenuCommands.swift
//
//
//  Which commands the status menu may offer on this Mac.
//
//  Here rather than in the menu builder for the reason `TempOverrideDisconnectPolicy` is:
//  `AppCore` has no test target, and a rule that decides whether a user is shown a button
//  that does nothing is worth pinning. `AppShared` cannot see `ChargeBackend` — it depends
//  only on `L10n` — so capabilities arrive as answered questions rather than as a backend
//  to re-interrogate, the same shape `ChargeControlFacts` uses.
//

import Foundation

public enum StatusMenuCommands {
    /// Whether "Inhibit Charging" should appear.
    ///
    /// - Parameter chargingCanBePausedOnDemand: `ChargeBackend.canPauseChargingOnDemand`
    ///   for this Mac. **Pass `true` while the backend is unknown**: every Mac that works
    ///   today can pause, and withholding the command from one that supports it because the
    ///   first diagnostics call had not landed is the worse of the two errors — the same
    ///   default `ChargingManager.backendCanPauseChargingOnDemand()` takes.
    public static func showsInhibitCharging(
        mode: AppChargingMode,
        chargingCanBePausedOnDemand: Bool
    ) -> Bool {
        guard mode.chargerConnected else { return false }
        // The gate the menu never had. Under `.systemChargeLimit` and `.firmwareRange` the
        // inhibit write is a no-op that succeeds, so the command reported success and paused
        // nothing — and on the way through it set a temporary limit at the current battery
        // level, which `ChargingManager` then deleted again on the next pass, writing the
        // user's visible System Settings limit twice for a request that could never land.
        guard chargingCanBePausedOnDemand else { return false }
        return mode.mode == .charging || mode.mode == .forceDischarge
    }
}
