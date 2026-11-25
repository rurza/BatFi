//
//  DelayAutomaticSleep.swift
//
//
//  Whether BatFi holds automatic sleep off while the battery charges up to the limit — the
//  "Delay automatic sleep when charging and the limit's not reached" setting.
//
//  The setting exists because BatFi stops charging at the limit by pausing it, and a
//  sleeping Mac cannot be told to pause. That premise only holds on a backend BatFi can
//  pause on demand. Under `.firmwareRange` and `.systemChargeLimit` the firmware or macOS
//  enforces the limit while the Mac sleeps, so keeping it awake protects nothing — and
//  worse, the system holds the battery a little below the limit there, so "below the limit
//  on mains" can stay true for hours and the Mac never auto-sleeps on AC.
//
//  Gated here rather than by clearing the stored preference, so the user's choice comes
//  back into effect on a Mac that regains a mechanism that can act on it.
//

import Foundation

public enum DelayAutomaticSleep {
    /// - Parameters:
    ///   - enabled: the user's `disableSleep` setting.
    ///   - batteryLevel: the current charge.
    ///   - limit: the limit in force for this pass.
    ///   - chargerConnected: the *resolved* connection, see `ChargerConnection`.
    ///   - backend: the resolved backend, or nil while it is unknown or unrecognized.
    ///   - sailingIsHolding: sailing is holding charge between the resume level and the
    ///     limit. Below the limit, but nothing is charging toward it, so there is no stop at
    ///     the limit for the Mac to stay awake for.
    ///
    /// An unknown backend keeps the ordinary behaviour — the same fail-open rule as the
    /// charging manager's other "can this Mac pause?" decisions. Every Mac that works today
    /// can pause, and the first diagnostics call not having landed yet is not evidence
    /// against it.
    public static func shouldPreventAutomaticSleep(
        enabled: Bool,
        batteryLevel: Int,
        limit: Int,
        chargerConnected: Bool,
        backend: ChargeBackend?,
        sailingIsHolding: Bool = false
    ) -> Bool {
        guard enabled, chargerConnected, batteryLevel < limit, !sailingIsHolding else { return false }
        return backend?.canPauseChargingOnDemand ?? true
    }
}
