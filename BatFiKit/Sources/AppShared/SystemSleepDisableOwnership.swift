//
//  SystemSleepDisableOwnership.swift
//  BatFi
//
//  Whether BatFi may write the system-wide `pmset disablesleep` flag.
//

import Foundation

/// Decides whether a request to disable or re-enable system sleep should actually reach
/// `pmset`, and who owns the flag afterwards.
///
/// `SleepDisabled` is **system-wide** and persistent: `sudo pmset -a disablesleep 1` is the
/// only reliable way to keep a Mac awake through a lid close, and people set it by hand for
/// exactly that reason. BatFi also needs it — a force discharge takes the adapter out of the
/// circuit, and only this flag survives a closed lid — so the two uses collide on one piece
/// of global state that carries no record of who set it.
///
/// BatFi used to guess, releasing the flag whenever a setting suggested it *might* be
/// holding one. Those release sites sit on the ordinary charging path, so a hand-set flag was
/// wiped within minutes, repeatedly, with no BatFi feature switched on that would explain it
/// (issue #148). The rule here replaces the guess: **BatFi clears only a flag it set itself,**
/// and it only counts as having set it if the flag was actually off beforehand.
public enum SystemSleepDisableOwnership {
    public struct Decision: Equatable, Sendable {
        /// Whether to send the `pmset` write at all.
        public let writes: Bool
        /// Whether BatFi holds the flag once this decision has been carried out.
        public let batFiHoldsIt: Bool

        public init(writes: Bool, batFiHoldsIt: Bool) {
            self.writes = writes
            self.batFiHoldsIt = batFiHoldsIt
        }
    }

    /// - Parameters:
    ///   - disable: what the caller is asking for — `true` to stop the Mac sleeping.
    ///   - batFiHoldsIt: whether a `true` BatFi wrote earlier is still outstanding.
    ///   - systemAlreadyDisabled: the live `SleepDisabled` value, or `nil` where it could not
    ///     be read — a helper too old to answer, a `pmset` that timed out.
    public static func decide(
        disable: Bool,
        batFiHoldsIt: Bool,
        systemAlreadyDisabled: Bool?
    ) -> Decision {
        guard disable else {
            // The fix. A release BatFi does not own is somebody else's flag, and on the
            // ordinary charging path this is by far the common case.
            guard batFiHoldsIt else { return Decision(writes: false, batFiHoldsIt: false) }
            return Decision(writes: true, batFiHoldsIt: false)
        }

        // Already ours: write again rather than assume. The flag is global, so something
        // else can have cleared it since, and a discharge that outlives its protection is
        // the failure this whole mechanism exists to prevent.
        if batFiHoldsIt { return Decision(writes: true, batFiHoldsIt: true) }

        // Somebody else's, and it is already in the state BatFi wants. Take the benefit
        // without taking ownership: whoever set it decides when it comes off.
        if systemAlreadyDisabled == true { return Decision(writes: false, batFiHoldsIt: false) }

        // Off, or unreadable. Claiming an unreadable flag is the safe way to be wrong —
        // BatFi then cleans up after itself, where declining to claim would strand a flag
        // nothing else releases.
        return Decision(writes: true, batFiHoldsIt: true)
    }

    /// Whether a flag already up the first time this version runs should be treated as one
    /// an **earlier BatFi** left behind.
    ///
    /// Versions before the ownership record kept "BatFi disabled sleep" in memory only, and
    /// re-enabled sleep on the next charging pass whether or not it was theirs to re-enable
    /// — the bug — which also meant a process that died mid-discharge healed itself on the
    /// next launch. The record removes the bug and the accidental healing with it, so this
    /// covers the upgrade: once, and only where an earlier version could actually have set
    /// the flag.
    ///
    /// - Parameters:
    ///   - systemAlreadyDisabled: the live `SleepDisabled` value, or `nil` where it could
    ///     not be read. Unknown adopts nothing: there is no write here whose flag could be
    ///     lost track of, only somebody else's to wrongly claim.
    ///   - disableSleepDuringDischarging: the setting that actually takes the flag. Not
    ///     `allowDischargingFullBattery`, which merely permits the discharge — reading that
    ///     as evidence of a held flag is precisely the guess issue #148 was made of.
    ///
    ///   One taker is deliberately not covered: a manual discharge on firmware that drains
    ///   to the limit itself disables sleep with no setting on at all. Nothing distinguishes
    ///   the flag it leaves from a hand-set one, and claiming on firmware alone would clear
    ///   a user's flag on every Mac of that generation. Left stranded on purpose — the
    ///   narrower harm.
    public static func adoptsFlagLeftByAnEarlierVersion(
        systemAlreadyDisabled: Bool?,
        disableSleepDuringDischarging: Bool
    ) -> Bool {
        systemAlreadyDisabled == true && disableSleepDuringDischarging
    }
}
