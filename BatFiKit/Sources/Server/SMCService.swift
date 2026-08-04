//
//  SMCService.swift
//
//
//  Created by Adam Różyński on 29/03/2024.
//

import Foundation
import os
import Sentry
import Shared

actor SMCService {
    private lazy var logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "SMC Service")
    /// Mirrors the driver connection, and is the only thing that may close it.
    /// `currentBackend()` refuses to cache a resolution unless this is true, so the
    /// flag and the connection must never disagree — a flag left true over a closed
    /// connection lets a racing request probe a dead driver and cache `.unsupported`.
    private var smcIsOpened = false {
        didSet {
            if !smcIsOpened && oldValue {
                SMCKit.close()
            }
        }
    }

    static let shared = SMCService()

    private init() { }

    private var cachedBackend: ChargeBackend?
    private var cachedBackendFirmware: String?

    /// Closes the driver connection through the flag rather than behind its back:
    /// `Listener`'s quit handler calls this directly, and a request racing that
    /// handler has to see `smcIsOpened == false`. Closing is the `didSet`'s job.
    func close() {
        smcIsOpened = false
    }

    /// Resolves the charge-control mechanism from the firmware's key table.
    ///
    /// Cached against the firmware token, not the macOS version, and re-probed when
    /// that token changes. This is the case a user hits by updating macOS, taking the
    /// new firmware, then downgrading macOS again — the OS moves, the firmware does
    /// not, and the cache follows the firmware.
    func currentBackend() async -> ChargeBackend {
        let firmware = SystemFirmware.version()
        if let cachedBackend, cachedBackendFirmware == firmware {
            return cachedBackend
        }

        await openSMCIfNeeded()
        // openSMCIfNeeded() cannot fail loudly — it exhausts its retries and returns
        // with smcIsOpened still false. Probing over a dead connection makes every key
        // look absent, which resolves to .unsupported and would then be cached against
        // this machine's real firmware token, pinning a resident daemon to "no charge
        // control" for its whole life over one transient open failure. Fail this call
        // only; the next one retries the open.
        guard smcIsOpened else {
            logger.error("SMC is not open; refusing to cache a backend resolution")
            return .unsupported
        }

        let capabilities = SMCKit.probeCapabilities(ChargeBackendResolver.probedKeys)
        let backend = ChargeBackendResolver.resolve(capabilities)

        let summary = capabilities.keys.sorted().joined(separator: ", ")
        logger.notice("""
        Charge backend resolved to \(backend.rawValue, privacy: .public) \
        on firmware \(firmware ?? "unknown", privacy: .public); usable keys: \(summary, privacy: .public)
        """)

        cachedBackend = backend
        cachedBackendFirmware = firmware
        return backend
    }

    func setChargingMode(_ message: SMCChargingCommand) async throws {
        let inhibitCharging: Bool
        let forceDischarge: Bool

        switch message {
        case .forceDischarging:
            forceDischarge = true
            inhibitCharging = false
            logger.notice("Handling force discharge")
        case .auto:
            forceDischarge = false
            inhibitCharging = false
            logger.notice("Handling enable charge")
        case .inhibitCharging:
            forceDischarge = false
            inhibitCharging = true
            logger.notice("Handling inhibit charging")
        }

        logger.notice("Setting SMC charging status")
        await openSMCIfNeeded()

        do {
            try await enableCharging(!inhibitCharging)
            try await enableForceDischarge(forceDischarge)
            if await PowerUICharging.shared.isMCLSupported, message == .auto {
                do {
                    try await PowerUICharging.shared.overrideMCLTarget(100)
                } catch {
                    logger.error("PowerUI MCL override failed: \(error, privacy: .public)")
                }
            }
        } catch {
            self.logger.critical("SMC writing error: \(error)")
            self.resetIfPossible()
            invalidateBackendCache()
            smcIsOpened = false
            throw error
        }
    }

    /// Clears the PowerUI MCL override (so the user's saved System Settings limit comes back)
    /// and sets SMC back to auto-charge. Used on app quit and when the user disables BatFi's
    /// charge management.
    func restoreSystemDefaults() async throws {
        if await PowerUICharging.shared.isMCLSupported {
            await PowerUICharging.shared.clearMCLOverride()
        }

        logger.notice("Restoring SMC defaults (auto charge, force discharge off)")
        await openSMCIfNeeded()

        do {
            // Force discharge is released first on purpose. It is the only state that
            // can drain the battery while the Mac sits on AC, and `enableCharging` can
            // throw transiently — with the charge write upstream, one such throw skipped
            // the release entirely and left the machine discharging until BatFi was
            // relaunched. Nothing downstream of this line can strand that state now.
            try await enableForceDischarge(false)
            try await enableCharging(true)
        } catch {
            logger.critical("SMC writing error while restoring defaults: \(error)")
            resetIfPossible()
            invalidateBackendCache()
            smcIsOpened = false
            throw error
        }
    }

    func mclStatus() async -> MCLStatus {
        if await PowerUICharging.shared.isMCLSupported {
            return await PowerUICharging.shared.mclStatus()
        }
        return MCLStatus(supported: false, batFiHasActiveOverride: false, lastOverrideValue: nil)
    }

    /// Snapshot for bug reports: resolved backend, firmware token, the firmware's own
    /// `CHNC` reason for not charging, and MCL status. Decoded and reported only — no
    /// control flow branches on `CHNC`, since which bit a `CHTE` inhibit raises has not
    /// been confirmed on hardware.
    func chargingDiagnostics() async -> ChargingDiagnostics {
        let backend = await currentBackend()
        let firmwareVersion = SystemFirmware.version()

        await openSMCIfNeeded()
        // Read defensively: CHNC may be absent on some firmware, and a diagnostics call
        // that throws is worse than useless. Absent or unreadable reports no reasons.
        let reasons: [String]
        if let bytes = try? SMCKit.readData(.notChargingReason) {
            let raw: [UInt8] = [
                bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5, bytes.6, bytes.7
            ]
            reasons = NotChargingReason.decode(raw).map(\.rawValue)
        } else {
            reasons = []
        }

        let mcl = await mclStatus()

        return ChargingDiagnostics(
            backend: backend.rawValue,
            firmwareVersion: firmwareVersion,
            notChargingReasons: reasons,
            mcl: mcl
        )
    }

    /// Best-effort return to a safe state after a write error.
    ///
    /// Invariant: **every key any engage path can write must be cleared here.** This
    /// is the last line of defence — callers use `try?` and one of them runs as the
    /// app exits, so a key left engaged here stays engaged. `CHIE` was missing from
    /// this list while `enableForceDischarge` wrote it, which is exactly how a Mac
    /// could be left draining on AC after a failed restore.
    func resetIfPossible() {
        // Try to reset new firmware keys first
        try? SMCKit.writeData(.inhibitCharging3, byte0: 0, byte1: 0, byte2: 0, byte3: 0)
        try? SMCKit.writeData(.disableCharging3, uint8: 0)

        // Also reset old firmware keys
        try? SMCKit.writeData(.disableCharging1, uint8: 0)
        try? SMCKit.writeData(.disableCharging2, uint8: 0)
        try? SMCKit.writeData(.inhibitCharging1, uint8: 0)
        try? SMCKit.writeData(.inhibitCharging2, uint8: 0)
    }

    /// Drops the resolved backend so the next call re-probes.
    ///
    /// Called from every failure path that can have resolved one: a probe run over a
    /// connection that is already degrading can answer for some keys and not others,
    /// and that partial table resolves to a backend this firmware does not have —
    /// cached against the machine's real firmware token, which pins it for the life of
    /// the daemon and makes every later call fail on a key that was never really
    /// missing. The MagSafe LED and power-distribution paths never reach the resolver,
    /// so they have nothing to drop.
    private func invalidateBackendCache() {
        cachedBackend = nil
        cachedBackendFirmware = nil
    }

    func smcChargingStatus() async throws -> SMCChargingStatus {
        logger.notice("Checking SMC status")
        await openSMCIfNeeded()
        do {
            logger.notice("Getting disable charging status")
            // Shape-checked rather than read-and-catch, and independently of the charge
            // backend — CHIE outlives CHTE on newer firmware.
            // CHIE and the legacy CH0I/CH0J all use 0 for "adapter connected". They do NOT
            // share one engaged value — CHIE is written 0x08 here (see
            // SMCKey.forceDischargeEngagedValue) but other tools have observed 0x20 as a
            // second isolated state for the same key — so we test for "not connected"
            // rather than matching one specific engaged byte. Both arms use the same test
            // deliberately: the write side is asymmetric, and letting the two read arms
            // diverge from each other (or from the write) is how this drifted out of sync
            // before.
            let forceDischarging: Bool
            if forceDischargeKeyIsUsable(.disableCharging3, writable: false), let data = try? SMCKit.readData(.disableCharging3) {
                forceDischarging = data.0 != 0
            } else if forceDischargeKeyIsUsable(.disableCharging1, writable: false), let data = try? SMCKit.readData(.disableCharging1) {
                forceDischarging = data.0 != 0
            } else {
                forceDischarging = false
                logger.error("Failed to read disable charging status")
            }

            logger.notice("Getting charging enabled status")
            let chargingEnabled = try await isChargingEnabled()
            
            logger.notice("Getting lid closed status")
            let lidClosed = try SMCKit.readData(SMCKey.lidClosed)

            return SMCChargingStatus(
                forceDischarging: forceDischarging,
                inhitbitCharging: !chargingEnabled,
                lidClosed: lidClosed.0 == 01
            )
        } catch {
            // Cleared here too, not only on the write paths: isChargingEnabled() above
            // resolves — and caches — a backend, and status is polled continuously while
            // writes happen only when the user changes mode. Without this, a resolution
            // made over a degrading connection would be re-read, fail, and be re-read
            // again for the life of the daemon with no write ever arriving to clear it.
            invalidateBackendCache()
            smcIsOpened = false
            throw error
        }
    }

    func magsafeLEDColor(_ option: MagSafeLEDOption) async throws -> MagSafeLEDOption {
        logger.notice("Setting MagSafe LED color")
        await openSMCIfNeeded()
        do {
            try SMCKit.writeData(SMCKey.magSafeLED, uint8: option.rawValue)
            let data = try SMCKit.readData(.magSafeLED)
            guard let option = MagSafeLEDOption(rawValue: data.0) else {
                throw SMCError.canNotCreateMagSafeLEDOption
            }
            return option
        } catch {
            smcIsOpened = false
            throw error
        }
    }

    func magsafeLEDColor() async throws -> MagSafeLEDOption {
        logger.notice("Getting MagSafe LED color")
        await openSMCIfNeeded()
        do {
            let data = try SMCKit.readData(.magSafeLED)
            guard let option = MagSafeLEDOption(rawValue: data.0) else {
                throw SMCError.canNotCreateMagSafeLEDOption
            }
            return option
        } catch {
            smcIsOpened = false
            throw error
        }
    }

    func getPowerDistribution() async throws -> PowerDistributionInfo {
        logger.notice("Getting power distribution")
        await openSMCIfNeeded()
        do {
            let rawBatteryPower = try SMCKit.readData(SMCKey.batteryPower)
            let rawExternalPower = try SMCKit.readData(SMCKey.externalPower)

            var batteryPower = Float(fromBytes: (rawBatteryPower.0, rawBatteryPower.1, rawBatteryPower.2, rawBatteryPower.3))
            var externalPower = Float(fromBytes: (rawExternalPower.0, rawExternalPower.1, rawExternalPower.2, rawExternalPower.3))

            if abs(batteryPower) < 0.01 {
                batteryPower = 0
            }
            if externalPower < 0.01 {
                externalPower = 0
            }

            let systemPower = batteryPower + externalPower

            return PowerDistributionInfo(batteryPower: batteryPower, externalPower: externalPower, systemPower: systemPower)
        } catch {
            smcIsOpened = false
            throw error
        }
    }


    private func openSMCIfNeeded() async {
        guard !self.smcIsOpened else { return  }

        logger.notice("Opening SMC...")
        await attemptToOpenSMC(withRetryAttempts: 3)
    }

    private func attemptToOpenSMC(withRetryAttempts attempts: Int) async {
        var currentAttempt = 0

        while currentAttempt < attempts {
            do {
                try await openSMC()
                self.smcIsOpened = true
                return
            } catch {
                currentAttempt += 1
                if currentAttempt < attempts {
                    logger.error("Failed to open SMC, retrying... (\(currentAttempt)/\(attempts))")
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    logger.error("Failed to open SMC after \(attempts) attempts. Giving up...")
                    logger.critical("SMC opening error: \(error)")
                    SentrySDK.capture(error: error)
                    return
                }
            }
        }
    }

    private func openSMC() async throws {
        logger.notice("Attempting to open SMC...")
        try SMCKit.open()
        logger.notice("SMC successfully opened!")
    }
    
    func isChargingEnabled() async throws -> Bool {
        logger.notice("Checking if charging is enabled")
        await openSMCIfNeeded()
        
        switch await currentBackend() {
        case .chte:
            let data = try SMCKit.readData(.inhibitCharging3)
            let isEnabled = data.0 == 0
            logger.notice("CHTE: charging enabled = \(isEnabled)")
            return isEnabled
        case .legacyCH0BC:
            let data = try SMCKit.readData(.inhibitCharging1)
            let isEnabled = data.0 == 0
            logger.notice("CH0B: charging enabled = \(isEnabled)")
            return isEnabled
        case .systemChargeLimit, .unsupported:
            // No SMC key backs charging control under either case: .systemChargeLimit
            // is driven through PowerUI instead (wired up separately), and .unsupported
            // has no mechanism at all.
            logger.error("No usable charge control mechanism on this firmware")
            throw SMCError.keyNotFound(code: "CHTE")
        }
    }
    
    func enableCharging(_ enable: Bool) async throws {
        if enable {
            logger.notice("Enabling charging")
        } else {
            logger.notice("Inhibit charging")
        }
        await openSMCIfNeeded()
        let enableByte: UInt8 = enable ? 0 : 1

        switch await currentBackend() {
        case .chte:
            try SMCKit.writeData(.inhibitCharging3, byte0: enableByte, byte1: 0, byte2: 0, byte3: 0)
            logger.notice("Inhibit charging changed using CHTE")
        case .legacyCH0BC:
            try SMCKit.writeData(.inhibitCharging1, uint8: enableByte)
            try SMCKit.writeData(.inhibitCharging2, uint8: enableByte)
            logger.notice("Inhibit charging changed using CH0B/CH0C")
        case .systemChargeLimit, .unsupported:
            // No SMC key backs charging control under either case: .systemChargeLimit
            // is driven through PowerUI instead (wired up separately), and .unsupported
            // has no mechanism at all.
            logger.error("No usable charge control mechanism on this firmware")
            throw SMCError.keyNotFound(code: "CHTE")
        }
    }

    /// Whether the firmware exposes a force-discharge key in the shape this code needs.
    ///
    /// Existence is not enough to gate on. `probeCapability` only promises a non-zero
    /// size, and a same-named key of another shape — or a read-only one — accepts the
    /// write and ignores it, so "Run on Battery" would report success while the battery
    /// never discharged. Same rule the backend resolver applies to `CHTE`/`CH0B`/`CH0C`.
    ///
    /// The shapes are measured, not derived from `SMCKey`: on Tahoe-era firmware `CHIE`
    /// reports `hex_`/1 with attributes 0xd4 (readable | writable), *not* the `ui8 ` its
    /// declaration implies — the size matches, so the write is unaffected, but a `ui8 `
    /// expectation here would reject a perfectly good key. `CH0I`/`CH0J` are absent on
    /// that firmware and could not be measured; their shape follows the declaration.
    private func forceDischargeKeyIsUsable(_ key: SMCKey, writable: Bool) -> Bool {
        guard let capability = SMCKit.probeCapability(for: key) else { return false }
        let expectedType = key.code == SMCKey.disableCharging3.code ? "hex_" : "ui8 "
        return capability.matches(type: expectedType, size: 1, writable: writable)
    }

    func enableForceDischarge(_ enable: Bool) async throws {
        if enable {
            logger.notice("Force discharge")
        } else {
            logger.notice("Turn off force discharge")
        }
        await openSMCIfNeeded()
        func engageByte(for key: SMCKey) -> UInt8 { enable ? key.forceDischargeEngagedValue : 0 }

        // Probed independently of the charge backend: CHIE survives on firmware that
        // has dropped CHTE, so deriving this from the backend would disable a feature
        // that still works.
        if forceDischargeKeyIsUsable(.disableCharging3, writable: true) {
            try SMCKit.writeData(.disableCharging3, uint8: engageByte(for: .disableCharging3))
            logger.notice("Force discharge changed using CHIE")
            return
        }
        // Gated on CH0I, the same key smcChargingStatus() gates its legacy read on, so
        // the write and read paths can never disagree about whether this mechanism
        // exists. CH0I and CH0J ship as a pair; if CH0J were somehow absent its write
        // below throws loudly rather than reporting a discharge that never engaged.
        if forceDischargeKeyIsUsable(.disableCharging1, writable: true) {
            try? SMCKit.writeData(.disableCharging1, uint8: engageByte(for: .disableCharging1))
            try SMCKit.writeData(.disableCharging2, uint8: engageByte(for: .disableCharging2))
            logger.notice("Force discharge changed using CH0I/CH0J")
            return
        }
        logger.error("No usable force discharge mechanism on this firmware")
        throw SMCError.keyNotFound(code: "CHIE")
    }
}
