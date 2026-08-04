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
    private var smcIsOpened = false {
        didSet {
            if !smcIsOpened && oldValue {
                close()
            }
        }
    }

    static let shared = SMCService()

    private init() { }

    private var cachedBackend: ChargeBackend?
    private var cachedBackendFirmware: String?

    func close() {
        SMCKit.close()
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
            try await enableCharging(true)
            try await enableForceDischarge(false)
        } catch {
            logger.critical("SMC writing error while restoring defaults: \(error)")
            resetIfPossible()
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

    func resetIfPossible() {
        // Try to reset new firmware keys first
        try? SMCKit.writeData(.inhibitCharging3, byte0: 0, byte1: 0, byte2: 0, byte3: 0)

        // Also reset old firmware keys
        try? SMCKit.writeData(.disableCharging1, uint8: 0)
        try? SMCKit.writeData(.disableCharging2, uint8: 0)
        try? SMCKit.writeData(.inhibitCharging1, uint8: 0)
        try? SMCKit.writeData(.inhibitCharging2, uint8: 0)
    }

    func smcChargingStatus() async throws -> SMCChargingStatus {
        logger.notice("Checking SMC status")
        await openSMCIfNeeded()
        do {
            logger.notice("Getting disable charging status")
            // Probed rather than read-and-catch, and independently of the charge
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
            if SMCKit.probeCapability(for: .disableCharging3) != nil, let data = try? SMCKit.readData(.disableCharging3) {
                forceDischarging = data.0 != 0
            } else if SMCKit.probeCapability(for: .disableCharging1) != nil, let data = try? SMCKit.readData(.disableCharging1) {
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
    
    func isChargingControlCapable() async -> Bool {
        logger.notice("Checking charging control capability")
        await openSMCIfNeeded()
        
        // Check for new firmware keys first
        do {
            _ = try SMCKit.readData(.inhibitCharging3)
            logger.notice("New firmware detected")
            return true
        } catch {
            // Try old firmware keys
            do {
                _ = try SMCKit.readData(.inhibitCharging1)
                _ = try SMCKit.readData(.inhibitCharging2)
                logger.notice("Old firmware detected")
                return true
            } catch {
                logger.warning("No charging control keys found")
                return false
            }
        }
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
        case .unsupported:
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
        case .unsupported:
            logger.error("No usable charge control mechanism on this firmware")
            throw SMCError.keyNotFound(code: "CHTE")
        }
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
        if SMCKit.probeCapability(for: .disableCharging3) != nil {
            try SMCKit.writeData(.disableCharging3, uint8: engageByte(for: .disableCharging3))
            logger.notice("Force discharge changed using CHIE")
            return
        }
        // Gated on CH0I, the same key smcChargingStatus() gates its legacy read on, so
        // the write and read paths can never disagree about whether this mechanism
        // exists. CH0I and CH0J ship as a pair; if CH0J were somehow absent its write
        // below throws loudly rather than reporting a discharge that never engaged.
        if SMCKit.probeCapability(for: .disableCharging1) != nil {
            try? SMCKit.writeData(.disableCharging1, uint8: engageByte(for: .disableCharging1))
            try SMCKit.writeData(.disableCharging2, uint8: engageByte(for: .disableCharging2))
            logger.notice("Force discharge changed using CH0I/CH0J")
            return
        }
        logger.error("No usable force discharge mechanism on this firmware")
        throw SMCError.keyNotFound(code: "CHIE")
    }
}
