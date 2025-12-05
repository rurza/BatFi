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

/// Represents which SMC key mode is available on this system
enum SMCKeyMode {
    case legacy      // Pre-macOS 26: CH0I, CH0B, CH0C, CHWA
    case modern      // macOS 26+: CHLS, CHIn
    case fallback    // Use pmset as last resort
}

actor SMCService {
    private lazy var logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "SMC Service")
    private var smcIsOpened = false {
        didSet {
            if !smcIsOpened && oldValue {
                close()
            }
        }
    }

    /// Cached key mode after detection
    private var detectedKeyMode: SMCKeyMode?

    /// Default charge limit percentage for system charge limit (80%)
    private let defaultChargeLimitPercentage: UInt8 = 80

    static let shared = SMCService()

    private init() { }

    func close() {
        SMCKit.close()
    }

    /// Detect which SMC keys are available on this system
    private func detectKeyMode() async -> SMCKeyMode {
        if let cached = detectedKeyMode {
            return cached
        }

        await openSMCIfNeeded()

        // Try modern keys first (macOS 26+)
        if SMCKit.isKeyAccessible(.chargeLimitSetting) {
            logger.notice("Detected modern SMC keys (macOS 26+)")
            detectedKeyMode = .modern
            return .modern
        }

        // Try legacy keys
        if SMCKit.isKeyAccessible(.disableCharging) {
            logger.notice("Detected legacy SMC keys (pre-macOS 26)")
            detectedKeyMode = .legacy
            return .legacy
        }

        // Fallback to pmset
        logger.warning("No accessible SMC keys found, using pmset fallback")
        detectedKeyMode = .fallback
        return .fallback
    }

    func setChargingMode(_ message: SMCChargingCommand) async throws {
        let keyMode = await detectKeyMode()

        switch keyMode {
        case .legacy:
            try await setChargingModeLegacy(message)
        case .modern:
            try await setChargingModeModern(message)
        case .fallback:
            try await setChargingModePmset(message)
        }
    }

    /// Legacy SMC key handling (pre-macOS 26)
    private func setChargingModeLegacy(_ message: SMCChargingCommand) async throws {
        let disableChargingByte: UInt8
        let inhibitChargingByte: UInt8
        let enableSystemChargeLimitByte: UInt8

        switch message {
        case .forceDischarging:
            disableChargingByte = 1
            inhibitChargingByte = 0
            enableSystemChargeLimitByte = 0
            logger.notice("Handling force discharge (legacy)")
        case .auto:
            disableChargingByte = 0
            inhibitChargingByte = 0
            enableSystemChargeLimitByte = 0
            logger.notice("Handling enable charge (legacy)")
        case .inhibitCharging:
            disableChargingByte = 0
            inhibitChargingByte = 02
            enableSystemChargeLimitByte = 0
            logger.notice("Handling inhibit charging (legacy)")
        case .enableSystemChargeLimit:
            disableChargingByte = 0
            inhibitChargingByte = 0
            enableSystemChargeLimitByte = 1
            logger.notice("Handling enable system charge limit (legacy)")
        }

        logger.notice("Setting SMC charging status (legacy keys)")
        await openSMCIfNeeded()

        do {
            try SMCKit.writeData(.disableCharging, uint8: disableChargingByte)
            try SMCKit.writeData(.inhibitChargingC, uint8: inhibitChargingByte)
            try SMCKit.writeData(.inhibitChargingB, uint8: inhibitChargingByte)
            try? SMCKit.writeData(.enableSystemChargeLimit, uint8: enableSystemChargeLimitByte)
        } catch {
            self.logger.critical("SMC writing error (legacy): \(error)")
            self.resetIfPossibleLegacy()
            smcIsOpened = false
            throw error
        }
    }

    /// Modern SMC key handling (macOS 26+)
    private func setChargingModeModern(_ message: SMCChargingCommand) async throws {
        logger.notice("Setting SMC charging status (modern keys)")
        await openSMCIfNeeded()

        do {
            switch message {
            case .forceDischarging:
                logger.notice("Handling force discharge (modern)")
                // Disable charge limit and try to force discharge
                try SMCKit.writeData(.chargeLimitSetting, percentage: 100, enabled: false)
                try? SMCKit.writeData(.chargeInhibit, uint8: 1)

            case .auto:
                logger.notice("Handling enable charge (modern)")
                // Disable all charging limits
                try SMCKit.writeData(.chargeLimitSetting, percentage: 100, enabled: false)
                try? SMCKit.writeData(.chargeInhibit, uint8: 0)

            case .inhibitCharging:
                logger.notice("Handling inhibit charging (modern)")
                // Enable charge inhibit
                try? SMCKit.writeData(.chargeInhibit, uint8: 1)

            case .enableSystemChargeLimit:
                logger.notice("Handling enable system charge limit (modern)")
                // Set CHLS to 80% enabled
                try SMCKit.writeData(.chargeLimitSetting, percentage: defaultChargeLimitPercentage, enabled: true)
                try? SMCKit.writeData(.chargeInhibit, uint8: 0)
            }
        } catch {
            self.logger.critical("SMC writing error (modern): \(error)")
            smcIsOpened = false
            throw error
        }
    }

    /// Fallback using pmset command
    private func setChargingModePmset(_ message: SMCChargingCommand) async throws {
        logger.notice("Using pmset fallback for charging control")

        let process = Process()
        process.launchPath = "/usr/bin/pmset"

        switch message {
        case .forceDischarging:
            // pmset doesn't support force discharge directly
            logger.warning("Force discharge not supported via pmset fallback")
            return

        case .auto:
            // Disable any battery limit
            process.arguments = ["-a", "batteryhealthmode", "0"]

        case .inhibitCharging:
            // Use battery health mode to inhibit
            process.arguments = ["-a", "batteryhealthmode", "1"]

        case .enableSystemChargeLimit:
            // Enable 80% charge limit via battery health mode
            process.arguments = ["-a", "batteryhealthmode", "1"]
        }

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                logger.error("pmset command failed with status: \(process.terminationStatus)")
            }
        } catch {
            logger.error("Failed to execute pmset: \(error)")
            throw error
        }
    }

    func resetIfPossible() {
        Task {
            let keyMode = await detectKeyMode()
            switch keyMode {
            case .legacy:
                resetIfPossibleLegacy()
            case .modern:
                resetIfPossibleModern()
            case .fallback:
                break // No reset needed for pmset
            }
        }
    }

    private func resetIfPossibleLegacy() {
        do {
            try SMCKit.writeData(.disableCharging, uint8: 0)
            try SMCKit.writeData(.inhibitChargingC, uint8: 0)
            try SMCKit.writeData(.inhibitChargingB, uint8: 0)
            try? SMCKit.writeData(.enableSystemChargeLimit, uint8: 0)
        } catch {
            smcIsOpened = false
            logger.critical("Resetting charging state failed (legacy). \(error)")
        }
    }

    private func resetIfPossibleModern() {
        do {
            try SMCKit.writeData(.chargeLimitSetting, percentage: 100, enabled: false)
            try? SMCKit.writeData(.chargeInhibit, uint8: 0)
        } catch {
            smcIsOpened = false
            logger.critical("Resetting charging state failed (modern). \(error)")
        }
    }

    func smcChargingStatus() async throws -> SMCChargingStatus {
        let keyMode = await detectKeyMode()

        switch keyMode {
        case .legacy:
            return try await smcChargingStatusLegacy()
        case .modern:
            return try await smcChargingStatusModern()
        case .fallback:
            return try await smcChargingStatusFallback()
        }
    }

    /// Get charging status using legacy SMC keys
    private func smcChargingStatusLegacy() async throws -> SMCChargingStatus {
        logger.notice("Checking SMC status (legacy)")
        await openSMCIfNeeded()
        do {
            logger.notice("Getting disable charging status")
            let forceDischarging = try SMCKit.readData(SMCKey.disableCharging)
            logger.notice("Getting inhibit charging C status")
            let inhibitChargingC = try SMCKit.readData(SMCKey.inhibitChargingC)
            logger.notice("Getting inhibit charging B status")
            let inhibitChargingB = try SMCKit.readData(SMCKey.inhibitChargingB)
            logger.notice("Getting system charge limit status")
            var systemChargeLimit: SMCBytes?
            do {
                systemChargeLimit = try SMCKit.readData(SMCKey.enableSystemChargeLimit)
            } catch {
                logger.warning("System charge limit can't be read")
            }
            logger.notice("Getting lid closed status")
            let lidClosed = try SMCKit.readData(SMCKey.lidClosed)

            return SMCChargingStatus(
                forceDischarging: forceDischarging.0 == 01,
                inhitbitCharging: (inhibitChargingC.0 == 02 && inhibitChargingB.0 == 02)
                || (inhibitChargingC.0 == 03 && inhibitChargingB.0 == 03),
                lidClosed: lidClosed.0 == 01,
                systemChargeLimit: (systemChargeLimit?.0 ?? 00) == 01
            )
        } catch {
            smcIsOpened = false
            throw error
        }
    }

    /// Get charging status using modern SMC keys (macOS 26+)
    private func smcChargingStatusModern() async throws -> SMCChargingStatus {
        logger.notice("Checking SMC status (modern)")
        await openSMCIfNeeded()

        // Read CHLS key (2 bytes: percentage, enabled flag)
        var chargeLimitEnabled = false
        var chargeInhibited = false

        do {
            let chargeLimitData = try SMCKit.readData(SMCKey.chargeLimitSetting)
            // Second byte is the enable flag
            chargeLimitEnabled = chargeLimitData.1 == 01
            logger.notice("Charge limit: \(chargeLimitData.0)%, enabled: \(chargeLimitEnabled)")
        } catch {
            logger.warning("CHLS key can't be read: \(error)")
        }

        // Read charge inhibit status
        do {
            let chargeInhibitData = try SMCKit.readData(SMCKey.chargeInhibit)
            chargeInhibited = chargeInhibitData.0 == 01
        } catch {
            logger.warning("CHIn key can't be read")
        }

        // Read lid status (should work on all versions)
        var lidIsClosed = false
        do {
            let lidClosed = try SMCKit.readData(SMCKey.lidClosed)
            lidIsClosed = lidClosed.0 == 01
        } catch {
            logger.warning("Lid status can't be read")
        }

        return SMCChargingStatus(
            forceDischarging: chargeInhibited && !chargeLimitEnabled,
            inhitbitCharging: chargeInhibited || chargeLimitEnabled,
            lidClosed: lidIsClosed,
            systemChargeLimit: chargeLimitEnabled
        )
    }

    /// Get charging status using pmset fallback
    private func smcChargingStatusFallback() async throws -> SMCChargingStatus {
        logger.notice("Checking charging status via pmset fallback")

        // Use pmset -g batt to get basic battery info
        let process = Process()
        process.launchPath = "/usr/bin/pmset"
        process.arguments = ["-g", "batt"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse output to determine charging state
            let isCharging = output.contains("charging") && !output.contains("not charging")
            let isDischarging = output.contains("discharging")

            return SMCChargingStatus(
                forceDischarging: isDischarging,
                inhitbitCharging: !isCharging && !isDischarging,
                lidClosed: false, // Can't determine from pmset
                systemChargeLimit: false
            )
        } catch {
            logger.error("Failed to get battery status via pmset: \(error)")
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
}
