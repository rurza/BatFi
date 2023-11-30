//
//  RouteHandler.swift
//  Helper
//
//  Created by Adam on 25/04/2023.
//

import Foundation
import Cocoa
import os
import Shared

final class RouteHandler {
    private lazy var logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "🧭")

    func charging(_ message: SMCChargingCommand) async throws {
        defer {
            logger.notice("Closing SMC")
            SMCKit.close()
        }
        logger.notice("Opening SMC")
        try SMCKit.open()
        logger.notice("SMC Opened")
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

        do {
            try SMCKit.writeData(.disableCharging, uint8: disableChargingByte)
            try SMCKit.writeData(.inhibitChargingC, uint8: inhibitChargingByte)
            try SMCKit.writeData(.inhibitChargingB, uint8: inhibitChargingByte)
            try SMCKit.writeData(.enableSystemChargeLimit, uint8: enableSystemChargeLimitByte)
        } catch {
            logger.error("SMC writing error: \(error)")
            reset()
            throw error
        }
    }

    func reset() {
        do {
            try SMCKit.writeData(.disableCharging, uint8: 0)
            try SMCKit.writeData(.inhibitChargingC, uint8: 0)
            try SMCKit.writeData(.inhibitChargingB, uint8: 0)
            try SMCKit.writeData(.enableSystemChargeLimit, uint8: 0)
        } catch {
            logger.critical("Resetting charging state failed. \(error)")
        }
    }

    func smcStatus(_ message: SMCStatusCommand) async throws -> SMCStatus {
        defer {
            SMCKit.close()
        }
        try SMCKit.open()

        switch message {
        case .status:
            let forceDischarging = try SMCKit.readData(SMCKey.disableCharging)
            let inhibitChargingC = try SMCKit.readData(SMCKey.inhibitChargingC)
            let inhibitChargingB = try SMCKit.readData(SMCKey.inhibitChargingB)
            let lidClosed = try SMCKit.readData(SMCKey.lidClosed)

            logger.notice("Checking SMC status")

            return SMCStatus(
                forceDischarging: forceDischarging.0 == 01,
                inhitbitCharging: (inhibitChargingC.0 == 02 && inhibitChargingB.0 == 02)
                || (inhibitChargingC.0 == 03 && inhibitChargingB.0 == 03),
                lidClosed: lidClosed.0 == 01
            )
        }
    }

    func magsafeLEDColor(_ option: MagSafeLEDOption) async throws -> MagSafeLEDOption {
        defer { SMCKit.close() }
        try SMCKit.open()
        try SMCKit.writeData(SMCKey.magSafeLED, uint8: option.rawValue)
        let data = try SMCKit.readData(.magSafeLED)
        guard let option = MagSafeLEDOption(rawValue: data.0) else { throw SMCError.canNotCreateMagSafeLEDOption }
        return option
    }
    
    func powerInfo() throws -> PowerInfo {
        defer {
            SMCKit.close()
        }
        try SMCKit.open()
        
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
        
        return PowerInfo(batteryPower: batteryPower, externalPower: externalPower, systemPower: systemPower)
    }
}
