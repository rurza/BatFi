//
//  InhibitChargingShortcut.swift
//
//
//  Whether Settings › Hotkeys offers the "Inhibit charging" shortcut on this Mac.
//
//  The status menu offers "Inhibit Charging" only where the Mac can hold charge at its
//  current level (`StatusMenuCommands.showsInhibitCharging`, `ManualInhibit.isAvailable`);
//  the shortcut recorder is the same command reached another way and has to follow it. The
//  row is hidden rather than greyed out, and the user's binding is left alone, so a Mac that
//  regains a mechanism that can hold charge gets the row and the key back without the user
//  doing anything. Both this and `ManualInhibit.isAvailable` answer
//  `canHoldChargeAtCurrentLevel`, so the row and the command cannot disagree.
//

import Foundation

public enum InhibitChargingShortcut {
    /// - Parameter rawBackend: the `lastKnownChargeBackend` cache, or nil where this Mac
    ///   has never answered. Taken raw because that is what the cache holds and what a view
    ///   can observe directly.
    ///
    /// An unknown or unrecognised backend offers the row, as BatFi always has — the same
    /// fail-open default as the status menu and the charging manager. The first diagnostics
    /// call not having landed yet is not evidence against it.
    public static func isOffered(rawBackend: String?) -> Bool {
        guard let rawBackend, let backend = ChargeBackend(rawValue: rawBackend) else { return true }
        return backend.canHoldChargeAtCurrentLevel
    }
}
