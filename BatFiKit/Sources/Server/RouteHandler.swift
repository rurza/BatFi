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

        switch message {
        case .forceDischarging:
            disableChargingByte = 1
            inhibitChargingByte = 0
            logger.notice("Handling force discharge")
        case .auto:
            disableChargingByte = 0
            inhibitChargingByte = 0
            logger.notice("Handling enable charge")
        case .inhibitCharging:
            disableChargingByte = 0
            inhibitChargingByte = 02
            logger.notice("Handling inhibit charging")
        }

        do {
            try SMCKit.writeData(.disableCharging, uint8: disableChargingByte)
            try SMCKit.writeData(.inhibitChargingC, uint8: inhibitChargingByte)
            try SMCKit.writeData(.inhibitChargingB, uint8: inhibitChargingByte)
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
    
    func powerSettingOption(_ option: PowerSettingOption) {
        guard
            let IOPMCopyPMPreferences = Private.IOPMCopyPMPreferences,
            let IOPMFeatureIsAvailable = Private.IOPMFeatureIsAvailable,
            let IOPMSetPMPreferences = Private.IOPMSetPMPreferences
        else {
            return
        }
        guard var preferences = IOPMCopyPMPreferences().takeUnretainedValue() as? [String: [String: Any]] else {
            return
        }
        for (source, settings) in option.settings {
            for sourceValue in source.allValues {
                guard 
                    let sourceKey = sourceValue.key,
                    preferences[sourceKey] != nil
                else {
                    continue
                }
                for setting in settings {
                    let settingKey: String
                    let settingValue: Any
                    switch setting {
                    case .powerMode(let powerMode):
                        if powerMode == .high {
                            guard IOPMFeatureIsAvailable(Private.kIOPMHighPowerModeKey as CFString, sourceKey as CFString) else {
                                continue
                            }
                        }
                        settingKey = Private.kIOPMLowPowerModeKey
                        settingValue = powerMode.rawValue
                    }
                    guard IOPMFeatureIsAvailable(settingKey as CFString, sourceKey as CFString) else {
                        continue
                    }
                    preferences[sourceKey]![settingKey] = settingValue
                }
            }
        }
        _ = IOPMSetPMPreferences(preferences as CFDictionary)
    }
}
