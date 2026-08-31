//
//  ChargeToFullCompletion.swift
//
//
//  Whether a "Charge to 100%" override has met its goal and may be retired.
//
//  Split out of `ChargingManager` for the reason `TempOverrideDisconnectPolicy` was: it is a
//  rule that *deletes something the user asked for*, `AppCore` has no test target, and the
//  two removal rules an override is subject to had the same defect for the same reason —
//  each read the state of the world without asking whether that state predated the click.
//

import Foundation

public enum ChargeToFullCompletion {
    /// Whether the override has finished charging and should be handed back.
    ///
    /// - Parameters:
    ///   - overrideLimit: the active override's target.
    ///   - batteryLevel: the current charge percentage.
    ///   - batteryLevelWhenArmed: what the battery read at the moment this override was
    ///     armed. **This is the whole rule.** "Reached 100%" is an event, and the level
    ///     alone cannot tell it from a battery that was already there — so an override armed
    ///     against a full battery satisfied its own removal condition on the next status
    ///     pass, about 100 ms later, and the click did nothing.
    ///
    ///     That window is not the instant it sounds like. `SystemChargeTopUp` records the
    ///     measurement: `UISOC` stays pinned at 100 long after macOS starts draining, so a
    ///     user watching a full battery come down and clicking "Charge to 100%" to stop it
    ///     is clicking during exactly this window, which is the one time the command is
    ///     worth anything.
    ///
    /// An override armed at full therefore never completes: it holds the battery where the
    /// user asked for it to be held, and ends the way every other override ends — cancelled
    /// from the menu, or dropped by `TempOverrideDisconnectPolicy` once the charger has been
    /// out long enough.
    public static func isReached(
        overrideLimit: Int,
        batteryLevel: Int,
        batteryLevelWhenArmed: Int
    ) -> Bool {
        guard overrideLimit >= 100, batteryLevel >= 100 else { return false }
        return batteryLevelWhenArmed < 100
    }
}
