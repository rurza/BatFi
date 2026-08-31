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
/// "Charge to 100%" override left over after you unplug) — and "left over" is meant
/// literally: the override has to have been in place before the charger came out. A
/// **discharge** override — the user explicitly choosing to **Run on Battery** — is never
/// stale: the charger being absent is exactly the state the user asked for, so it must
/// persist until turned off manually.
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
    ///   - overrideArmedBeforeDisconnect: whether this override was already in place when
    ///     the charger came out. Only an override that was is *left over* from a charging
    ///     session, which is the whole thing this rule cleans up. One armed after the
    ///     disconnect is a standing request for the next one, and the clock — measured from
    ///     the charger transition, not from the click — had already run out before it was
    ///     made, so it was deleted on the status pass that followed the click.
    public static func decision(
        chargerConnected: Bool,
        batteryLevel: Int,
        overrideLimit: Int,
        secondsSinceDisconnect: TimeInterval?,
        overrideArmedBeforeDisconnect: Bool
    ) -> Decision {
        // A discharge override — battery sitting above the override's limit, i.e. the user
        // asking to run on battery — must persist: an absent charger is the requested state,
        // not a reason to drop it. Charge / hold overrides (battery at or below the limit)
        // remain subject to the prolonged-disconnect cleanup.
        let isDischargeOverride = batteryLevel > overrideLimit
        guard !chargerConnected, !isDischargeOverride else { return .keep }
        // An override armed *after* the charger came out cannot be left over from a charging
        // session; it is a request for the next one. Kept outright rather than given a clock
        // of its own: two minutes is as fatal to "tick this before I leave so it tops up when
        // I plug in" as no time at all, only less obviously.
        guard overrideArmedBeforeDisconnect else { return .keep }
        guard let secondsSinceDisconnect else { return .keep }
        let remaining = prolongedDisconnectTimeout - secondsSinceDisconnect
        guard remaining > 0 else { return .removeNow }
        return .scheduleRemoval(after: remaining)
    }
}
