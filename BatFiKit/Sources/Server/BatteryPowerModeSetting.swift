//
//  BatteryPowerModeSetting.swift
//
//
//  Low Power Mode per power source, read and written through `pmset`. The XPC calls and
//  the restore on exit both go through here, so both refuse the same arguments: nothing
//  reaches `pmset` that `PowerModeXPCArguments` did not build.
//

import Foundation
import Shared

enum BatteryPowerModeSetting {
    /// Each profile's setting as `pmset -g custom` reports it, or `nil` where `pmset` could
    /// not be read or publishes neither `powermode` nor `lowpowermode`.
    static func read(timeout: Duration) async -> PowerModeBySource? {
        guard let output = await Subprocess.standardOutput(
            of: XPCServiceHandler.pmset,
            arguments: ["-g", "custom"],
            timeout: timeout
        ) else { return nil }
        return PmsetCustomOutput.powerModeBySource(in: output)
    }

    /// Sets the battery profile alone (`pmset -b`), leaving the AC profile — the other half
    /// of the user's System Settings choice — untouched.
    ///
    /// Throws without running `pmset` for a value BatFi never writes under that key.
    static func write(_ value: UInt8, usesPowermodeKey: Bool, timeout: Duration) async throws {
        let key = PowerModeBySource.pmsetKey(usesPowermodeKey: usesPowermodeKey)
        guard let arguments = PowerModeXPCArguments.pmsetBatteryWrite(value, usesPowermodeKey: usesPowermodeKey) else {
            throw XPCServiceHandler.pmsetError("\(value) is not a battery \(key) value BatFi writes")
        }
        guard await Subprocess.run(XPCServiceHandler.pmset, arguments: arguments, timeout: timeout) else {
            throw XPCServiceHandler.pmsetError("Could not set battery \(key) to \(value)")
        }
    }
}
