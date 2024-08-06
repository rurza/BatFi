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
        let disableChargingByte: UInt8
        let inhibitChargingByte: UInt8
        let enableSystemChargeLimitByte: UInt8

        switch message {
        case .forceDischarging:
            disableChargingByte = 1
            inhibitChargingByte = 0
            enableSystemChargeLimitByte = 0
            logger.notice("Handling force discharge")
        case .auto:
            disableChargingByte = 0
            inhibitChargingByte = 0
            enableSystemChargeLimitByte = 0
            logger.notice("Handling enable charge")
        case .inhibitCharging:
            disableChargingByte = 0
            inhibitChargingByte = 02
            enableSystemChargeLimitByte = 0
            logger.notice("Handling inhibit charging")
        case .enableSystemChargeLimit:
            disableChargingByte = 0
            inhibitChargingByte = 0
            enableSystemChargeLimitByte = 1
            logger.notice("Handling enable system charge limit")
        }

        logger.notice("Setting SMC charging status")
        await openSMCIfNeeded()

        do {
            try SMCKit.writeData(.disableCharging, uint8: disableChargingByte)
            try SMCKit.writeData(.inhibitChargingC, uint8: inhibitChargingByte)
            try SMCKit.writeData(.inhibitChargingB, uint8: inhibitChargingByte)
            try? SMCKit.writeData(.enableSystemChargeLimit, uint8: enableSystemChargeLimitByte)
        } catch {
            self.logger.critical("SMC writing error: \(error)")
            self.resetIfPossible()
            smcIsOpened = false
        }
    }

    func resetIfPossible() {
        do {
            try SMCKit.writeData(.disableCharging, uint8: 0)
            try SMCKit.writeData(.inhibitChargingC, uint8: 0)
            try SMCKit.writeData(.inhibitChargingB, uint8: 0)
            try? SMCKit.writeData(.enableSystemChargeLimit, uint8: 0)
        } catch {
            smcIsOpened = false
            logger.critical("Resetting charging state failed. \(error)")
        }
    }

    func smcChargingStatus() async throws -> SMCChargingStatus {
        logger.notice("Checking SMC status")
        await openSMCIfNeeded()
        do {
            logger.notice("Getting disbale charging status")
            let forceDischarging = try SMCKit.readData(SMCKey.disableCharging)
            logger.notice("Getting inhibit charging C status")
            let inhibitChargingC = try SMCKit.readData(SMCKey.inhibitChargingC)
            logger.notice("Getting inhibit charging B status")
            let inhibitChargingB = try SMCKit.readData(SMCKey.inhibitChargingB)
            logger.notice("Getting system charge limit status")
            let systemChargeLimit = try? SMCKit.readData(SMCKey.enableSystemChargeLimit)
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
