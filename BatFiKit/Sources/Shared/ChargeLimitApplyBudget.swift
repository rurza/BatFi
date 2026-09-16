//
//  ChargeLimitApplyBudget.swift
//
//
//  How long applying a charge limit is allowed to take, stated once for both ends of the XPC
//  call.
//
//  Part of the contract rather than an implementation detail of either side. The helper's wait
//  and the app's watchdog are answers to the same question — how long is this call entitled to
//  run before silence means something is wrong — and they were written in different modules,
//  from different reasoning, without either knowing the other's number. They disagreed by 30
//  seconds.
//
//  Measured 2026-09-16 on the shipped app, applying a 75% limit: PowerUI refused the sub-80
//  value, `ManualChargeLimitDefaults` began its adoption wait at 12:48:54, and the app tore the
//  connection down at 12:49:09 — `Helper did not answer within 15s` — while the helper went on
//  working and reported the real outcome at 12:49:39, into a connection that no longer existed.
//  The app recorded `Failed to apply charge limit 75%` and, because `applyChargeLimit` returning
//  nil falls back to the value that was *requested*, spent the following passes believing 75%
//  was in force while powerd held 80%.
//
//  `quitTimeout` in `XPCClient` already states the principle: a client budget is sized to clear
//  the far side's ceiling rather than to expire on top of it, because expiring on top of it
//  reports a failure for a helper that was doing exactly what it was asked.
//

import Foundation

public enum ChargeLimitApplyBudget {
    /// How long the helper waits for powerd to adopt a limit written through PowerUIAgent's
    /// preference domain.
    ///
    /// Deliberately far larger than the write takes — see `ManualChargeLimitDefaults.apply`,
    /// where a write whose adoption had not appeared after six seconds landed anyway, with
    /// powerd's plist rewritten roughly half a minute later. Giving up early does not merely
    /// report a slow apply, it makes the caller overwrite an adoption still in flight.
    public static let adoptionCeiling: Duration = .seconds(45)

    /// The app's watchdog for one apply.
    ///
    /// The ceiling plus the work either side of it: `clearMCLOverride`, the `adoptSystemLimit`
    /// attempt that has to be refused before the defaults path is reached at all, and the reply
    /// crossing back. Sized off the ceiling rather than restated, so raising one raises both.
    public static let clientTimeout: Duration = adoptionCeiling + .seconds(15)

    /// The app's watchdog for a charge-resume nudge, which is **two** applies: the nudged value
    /// and then the user's own target put back. Each can spend the full ceiling, and the first
    /// one timing out is explicitly swallowed so that the restore still happens — so the call
    /// can legitimately run for twice as long as any other.
    public static let nudgeClientTimeout: Duration = adoptionCeiling * 2 + .seconds(15)
}
