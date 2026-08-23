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
}
