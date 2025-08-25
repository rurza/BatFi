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

    func close() {
        SMCKit.close()
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
        } catch {
            self.logger.critical("SMC writing error: \(error)")
            self.resetIfPossible()
            smcIsOpened = false
            throw error
        }
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
            let forceDischarging: Bool
            if let forceDischarging2 = try? SMCKit.readData(.disableCharging3) {
                forceDischarging = forceDischarging2.0 == 1
            } else if let forceDischarging1 = try? SMCKit.readData(.disableCharging1) {
                forceDischarging = forceDischarging1.0 == 1
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
        
        // Check for new firmware first
        do {
            let data = try SMCKit.readData(.inhibitCharging3)
            let isEnabled = data.0 == 0
            logger.notice("New firmware: charging enabled = \(isEnabled)")
            return isEnabled
        } catch {
            // Try old firmware
            do {
                let data1 = try SMCKit.readData(.inhibitCharging1)
                let isEnabled = data1.0 == 0
                logger.notice("Old firmware: charging enabled = \(isEnabled)")
                return isEnabled
            } catch {
                throw error
            }
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

        // Try new firmware first
        do {
            try SMCKit.writeData(.inhibitCharging3, byte0: enableByte, byte1: 0, byte2: 0, byte3: 0)
            logger.notice("Inhibit charging changed using new firmware")
        } catch {
            // Fallback to old firmware
            do {
                try SMCKit.writeData(.inhibitCharging1, uint8: enableByte)
                try SMCKit.writeData(.inhibitCharging2, uint8: enableByte)
                logger.notice("Inhibit charging changed using old firmware")
            } catch {
                throw error
            }
        }
    }

    func enableForceDischarge(_ enable: Bool) async throws {
        if enable {
            logger.notice("Force discharge")
        } else {
            logger.notice("Turn off force discharge")
        }
        await openSMCIfNeeded()
        let enableByte: UInt8 = enable ? 1 : 0

        do {
            try SMCKit.writeData(.disableCharging3, uint8: enableByte)
            logger.notice("Force discharge changed using new firmware")
        } catch {
            logger.error("Force discharge state change failed with new firmware. Using old as fallback")
            do {
                try? SMCKit.writeData(.disableCharging1, uint8: enableByte)
                try SMCKit.writeData(.disableCharging2, uint8: enableByte)
                logger.notice("Force discharge changed using old firmware")
            } catch {
                logger.error("Force discharge failed with old firmware")
                throw error
            }
        }
    }
}
