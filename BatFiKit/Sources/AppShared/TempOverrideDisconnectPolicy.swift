//
//  TempOverrideDisconnectPolicy.swift
//  BatFi
//
//  Pure decision logic for auto-removing a temporary charging override after the
//  power adapter has been disconnected.
//

import Foundation

/// Decides whether a temporary charging override should be automatically removed
/// after the power adapter has been disconnected.
///
/// A temp override is treated as *stale* once the charger has been gone for a prolonged
/// period **while the override is still trying to charge or hold** the battery (e.g. the
/// "Charge to 100%" override left over after you unplug). A **discharge** override — the
/// user explicitly choosing to **Run on Battery** — is never stale: the charger being
/// absent is exactly the state the user asked for, so it must persist until turned off
/// manually.
public enum TempOverrideDisconnectPolicy {
    /// How long the charger must stay disconnected before a charge/hold override is dropped.
    public static let prolongedDisconnectTimeout: TimeInterval = 120

    public enum Decision: Equatable, Sendable {
        /// Leave the override in place (and cancel any pending removal).
        case keep
        /// Remove the override immediately.
        case removeNow
        /// Remove the override after the given delay, provided the charger stays disconnected.
        case scheduleRemoval(after: TimeInterval)
    }

    /// - Parameters:
    ///   - chargerConnected: whether the power adapter is currently connected.
    ///   - batteryLevel: the current battery percentage.
    ///   - overrideLimit: the active override's target limit.
    ///   - secondsSinceDisconnect: how long the charger has been disconnected, or `nil`
    ///     if no disconnect has been recorded.
    public static func decision(
        chargerConnected: Bool,
        batteryLevel: Int,
        overrideLimit: Int,
        secondsSinceDisconnect: TimeInterval?
    ) -> Decision {
        // A discharge override — battery sitting above the override's limit, i.e. the user
        // asking to run on battery — must persist: an absent charger is the requested state,
        // not a reason to drop it. Charge / hold overrides (battery at or below the limit)
        // remain subject to the prolonged-disconnect cleanup.
        let isDischargeOverride = batteryLevel > overrideLimit
        guard !chargerConnected, !isDischargeOverride else { return .keep }
        guard let secondsSinceDisconnect else { return .keep }
        let remaining = prolongedDisconnectTimeout - secondsSinceDisconnect
        guard remaining > 0 else { return .removeNow }
        return .scheduleRemoval(after: remaining)
    }
}
