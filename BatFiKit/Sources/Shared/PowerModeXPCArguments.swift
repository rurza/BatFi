//
//  PowerModeXPCArguments.swift
//  BatFi
//
//  What the battery-only Low Power Mode calls carry across XPC, and what the helper will
//  accept of it. The helper runs `pmset` as root with these values, so nothing reaches it
//  that `AutoLowPowerModePolicy` could not have produced. Pure, so that line is a unit test.
//

import Foundation

public enum PowerModeXPCArguments {
    /// The `pmset` arguments that set the battery profile's Low Power Mode to `value`, or
    /// `nil` where `value` is not one BatFi writes under that key.
    ///
    /// The key is chosen here from a `Bool`, so it can only ever be one of the two known
    /// settings; the value is checked against the policy's own notion of what it writes.
    public static func pmsetBatteryWrite(_ value: UInt8, usesPowermodeKey: Bool) -> [String]? {
        guard AutoLowPowerModePolicy.canWrite(value, usesPowermodeKey: usesPowermodeKey) else {
            return nil
        }
        return ["-b", PowerModeBySource.pmsetKey(usesPowermodeKey: usesPowermodeKey), "\(value)"]
    }

    /// The record the helper holds to restore on exit, rebuilt from the fields
    /// `armPowerModeRestoreOnExit` carries, or `nil` where they are not ones the policy
    /// could have produced.
    ///
    /// Strict because `restoreValue` is written as root when the helper exits: it must be a
    /// value a restore can write back, and `written` must be low power — BatFi never takes a
    /// Low Power Mode that was already on, so no real record asks for anything else. The AC
    /// value is only ever compared, never written, but it still has to be a byte: one that
    /// wrapped on the way in would make a changed setting look untouched.
    ///
    /// - Parameter armedAt: stands in for `engagedAt`, which ownership does not look at.
    public static func exitRestoreRecord(
        restoreValue: NSNumber,
        written: UInt8,
        acAtWrite: NSNumber?,
        usesPowermodeKey: Bool,
        armedAt: Date
    ) -> AutoLowPowerModeRecord? {
        guard let previous = byte(restoreValue),
              AutoLowPowerModePolicy.canRestore(previous, usesPowermodeKey: usesPowermodeKey),
              written == AutoLowPowerModePolicy.lowPowerValue
        else { return nil }

        var acValue: UInt8?
        if let acAtWrite {
            guard let ac = byte(acAtWrite) else { return nil }
            acValue = ac
        }

        return AutoLowPowerModeRecord(
            usesPowermodeKey: usesPowermodeKey,
            previousBatteryValue: previous,
            writtenBatteryValue: written,
            acValueAtWrite: acValue,
            engagedAt: armedAt
        )
    }

    /// The live setting from `powerModeBySource`'s reply, or `nil` where the helper had
    /// nothing to report.
    ///
    /// The helper answers with neither value only when `pmset` could not be read or
    /// published neither key, so an empty reply is "unknown" — never a reading in which
    /// both profiles happen to be absent.
    public static func powerModeBySource(
        battery: NSNumber?,
        ac: NSNumber?,
        usesPowermodeKey: Bool
    ) -> PowerModeBySource? {
        guard battery != nil || ac != nil else { return nil }
        return PowerModeBySource(
            battery: battery.flatMap(byte),
            ac: ac.flatMap(byte),
            usesPowermodeKey: usesPowermodeKey
        )
    }

    /// `number` as a byte, or `nil` where it is not a whole number from 0 through 255.
    ///
    /// Not `uint8Value`, which wraps: 256 would arrive as 0 — a real setting.
    public static func byte(_ number: NSNumber) -> UInt8? {
        UInt8(exactly: number.doubleValue)
    }
}
