//
//  XPCService.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Foundation

@objc
public protocol XPCService {
    func setForceDischarge(_ handler: @escaping (Error?) -> Void)
    func setInhibitCharge(_ handler: @escaping (Error?) -> Void)
    func setAutocharge(_ handler: @escaping (Error?) -> Void)
    func restoreSystemDefaults(_ handler: @escaping (Error?) -> Void)
    /// Applies a charge limit and answers with the limit **actually** applied, which can
    /// differ from the one requested: under Apple's Manual Charge Limit the mechanism
    /// cannot go below 80%, so a lower request comes back raised.
    ///
    /// `UInt8` on both sides for the reason `setMagSafeLEDColor` uses it — an `@objc`
    /// reply cannot carry a Swift `Int`. A percentage fits a byte with room to spare,
    /// which leaves `UInt8.max` free to serve as the failure sentinel here exactly as it
    /// does there: it is not a value this reply can otherwise hold, so it can never be
    /// mistaken for a real answer. The error is still passed alongside it.
    func applyChargeLimit(_ percentage: UInt8, _ handler: @escaping (UInt8, Error?) -> Void)
    /// `applyChargeLimit` with a resume level: where the firmware holds a band, the band
    /// reaches down to `lower` instead of a fixed few points under `upper`. Every other
    /// mechanism applies `upper` exactly as `applyChargeLimit` does. Same reply, same
    /// `UInt8.max` sentinel.
    ///
    /// A separate call rather than a new parameter on `applyChargeLimit`, so an older app
    /// keeps working against this helper. The reverse does not hold: a helper older than
    /// 4.2.0 does not know this call and **drops** the message without replying, so the app
    /// checks the running helper's version before asking — see `ChargeRangeCall`.
    func applyChargeRange(_ upper: UInt8, lower: UInt8, _ handler: @escaping (UInt8, Error?) -> Void)
    /// Applies a charge limit **as if none had ever been applied**, and answers with the
    /// limit actually put in force.
    ///
    /// Same shape and same `UInt8.max` sentinel as `applyChargeLimit`, and a separate call
    /// rather than a flag on it because the two say different things. `applyChargeLimit`
    /// runs on every status update and is expected to write nothing when the limit it
    /// recorded is the one asked for; this is the app reporting that the recorded limit is
    /// not what the battery is doing, so the record is what must not be trusted.
    func reassertChargeLimit(_ percentage: UInt8, _ handler: @escaping (UInt8, Error?) -> Void)
    func nudgeChargeLimit(
        to nudgeValue: UInt8,
        restoring target: UInt8,
        _ handler: @escaping (Bool, Error?) -> Void
    )
    func getMCLStatus(_ handler: @escaping (MCLStatus?, Error?) -> Void)
    func getChargingDiagnostics(_ handler: @escaping (ChargingDiagnostics?, Error?) -> Void)
    func getCurrentChargingStatus(_ handler: @escaping (SMCChargingStatus?, Error?) -> Void)
    func getPowerDistribution(_ handler: @escaping (PowerDistributionInfo?, Error?) -> Void)
    func setMagSafeLEDColor(color: UInt8, _ handler: @escaping (UInt8, Error?) -> Void)
    func getMagSafeLEDOption(_ handler: @escaping (UInt8, Error?) -> Void)
    func ping(_ handler: @escaping (Bool, Error?) -> Void)
    func quit(_ handler: @escaping (Bool, Error?) -> Void)
    func turnPowerMode(_ mode: UInt8, lowPowerModeOnly: Bool, _ handler: @escaping (Error?) -> Void)
    /// Boolean is telling us if the high power mode is available
    func currentPowerMode(_ handler: @escaping (NSNumber?, Bool) -> Void)
    func disableAutosleep(_ disable: Bool, _ handler: @escaping (Error?) -> Void)
    /// The live system-wide `SleepDisabled` value: `true` where something has disabled
    /// sleep outright, `false` otherwise, and `nil` where `pmset` could not be read.
    ///
    /// Asked before BatFi disables sleep itself, so it can tell a flag it set from one that
    /// was already there — see `SystemSleepDisableOwnership`. `nil` is a real answer here
    /// rather than an error: the caller has a defined behaviour for "unknown", and a helper
    /// too old to implement this at all fails the call, which reaches the same branch.
    func sleepIsDisabled(_ handler: @escaping (NSNumber?) -> Void)
    /// Low Power Mode for each power source, from `pmset -g custom` — unlike
    /// `currentPowerMode`, which reads only the value in use and so cannot tell "on for the
    /// battery" from "on everywhere".
    ///
    /// `usesPowermodeKey` says which setting the values were read from, and so which one to
    /// write back under. Both values `nil` means `pmset` could not be read; that, and a
    /// helper too old to implement this, is "unknown" to the caller.
    func powerModeBySource(_ handler: @escaping (_ battery: NSNumber?, _ ac: NSNumber?, _ usesPowermodeKey: Bool) -> Void)
    /// Sets Low Power Mode for the battery profile only (`pmset -b`). Unlike `turnPowerMode`,
    /// the AC profile — the other half of the user's System Settings choice — is untouched.
    ///
    /// Refused with an error, without running `pmset`, for a value BatFi never writes under
    /// that key: 0, 1 or 2 under `powermode`, 0 or 1 under `lowpowermode`.
    func setBatteryPowerMode(_ value: UInt8, usesPowermodeKey: Bool, _ handler: @escaping (Error?) -> Void)
    /// Hands the helper what to give back if it exits while BatFi holds Low Power Mode on
    /// the battery: `restoreValue` is written back under the key if the battery value is
    /// still `written` and the AC value still `acAtWrite` (where one was seen). A `nil`
    /// `restoreValue` disarms it.
    ///
    /// Held in memory only; refused with an error for fields the app's own policy could not
    /// have produced.
    func armPowerModeRestoreOnExit(
        _ restoreValue: NSNumber?,
        written: UInt8,
        acAtWrite: NSNumber?,
        usesPowermodeKey: Bool,
        _ handler: @escaping (Error?) -> Void
    )
}
