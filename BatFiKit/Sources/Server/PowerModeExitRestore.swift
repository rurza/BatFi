//
//  PowerModeExitRestore.swift
//
//
//  Gives the battery profile's Low Power Mode setting back when the helper exits, if the
//  app turned it on and nobody has changed it since.
//
//  The app persists what it took before it writes, and gives it back itself on the charger,
//  on quit, and at the next launch after a crash. This covers the stretch in between: the
//  helper exits when the app's process dies, however it dies, so a copy of the record held
//  here is what puts the value back when the app never got the chance to. The app arms it
//  after it writes and disarms it once the value is back.
//

import Foundation
import os
import Shared

final class PowerModeExitRestore: @unchecked Sendable {
    static let shared = PowerModeExitRestore()

    /// Each `pmset` call's ceiling here. `pmset` answers in milliseconds; this only bounds a
    /// wedged one, and a read plus a write under it fit inside the budget `HelperShutdown`
    /// gives this whole restore.
    private static let pmsetTimeout: Duration = .seconds(1)

    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "PowerModeExitRestore")
    private let lock = NSLock()
    /// In memory only: it is the helper's exit it serves, and a helper that starts again is
    /// re-armed by the app.
    private var armed: AutoLowPowerModeRecord?

    private init() {}

    func arm(_ record: AutoLowPowerModeRecord) {
        lock.withLock { armed = record }
        logger.notice(
            "Armed: on exit, battery \(Self.key(of: record), privacy: .public) goes back to \(record.previousBatteryValue, privacy: .public) if it is still \(record.writtenBatteryValue, privacy: .public) with AC at \(String(describing: record.acValueAtWrite), privacy: .public)"
        )
    }

    func disarm() {
        let wasArmed = lock.withLock {
            defer { armed = nil }
            return armed != nil
        }
        if wasArmed {
            logger.notice("Disarmed the Low Power Mode restore on exit")
        }
    }

    /// Writes the armed record's previous battery value back, if the live setting is still
    /// exactly what BatFi left — `AutoLowPowerModePolicy.isStillOwned`, the question the app
    /// asks too. Anything else is the user's choice, made since, and is left alone.
    ///
    /// Takes the record, so it runs at most once per arm. Never acts blind: a setting that
    /// cannot be read is not written.
    func restoreIfStillOwned() async {
        let record = lock.withLock {
            defer { armed = nil }
            return armed
        }
        guard let record else { return }
        let key = Self.key(of: record)

        guard let live = await BatteryPowerModeSetting.read(timeout: Self.pmsetTimeout) else {
            logger.error("Could not read \(key, privacy: .public) before exiting; leaving the battery setting as it is")
            return
        }
        guard AutoLowPowerModePolicy.isStillOwned(record, live: live) else {
            logger.notice(
                "Battery \(key, privacy: .public) changed since BatFi set it (battery \(String(describing: live.battery), privacy: .public), AC \(String(describing: live.ac), privacy: .public), key \(PowerModeBySource.pmsetKey(usesPowermodeKey: live.usesPowermodeKey), privacy: .public)); leaving it to the user"
            )
            return
        }
        do {
            try await BatteryPowerModeSetting.write(
                record.previousBatteryValue,
                usesPowermodeKey: record.usesPowermodeKey,
                timeout: Self.pmsetTimeout
            )
            logger.notice("Restored battery \(key, privacy: .public) to \(record.previousBatteryValue, privacy: .public) before exiting")
        } catch {
            logger.error("Could not restore battery \(key, privacy: .public) before exiting: \(error, privacy: .public)")
        }
    }

    private static func key(of record: AutoLowPowerModeRecord) -> String {
        PowerModeBySource.pmsetKey(usesPowermodeKey: record.usesPowermodeKey)
    }
}
