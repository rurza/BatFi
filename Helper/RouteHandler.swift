//
//  RouteHandler.swift
//  Helper
//
//  Created by Adam on 25/04/2023.
//

import Foundation

final class RouteHandler {
    static func charging(_ message: SMCChargingCommand) throws {
        defer { SMCKit.close() }
        try SMCKit.open()

        let disableChargingByte: UInt8
        let inhibitChargingByte: UInt8

        switch message {
        case .forceDischarging:
            disableChargingByte = 1
            inhibitChargingByte = 0
        case .auto:
            disableChargingByte = 0
            inhibitChargingByte = 0
        case .inhibitCharging:
            disableChargingByte = 0
            inhibitChargingByte = 1
        }

        try SMCKit.writeData(.disableCharging, uint8: disableChargingByte)
        try SMCKit.writeData(.inhibitCharging, uint8: inhibitChargingByte)
    }

    static func smcStatus(_ message: SMCStatusCommand) throws -> SMCStatus {
        defer { SMCKit.close() }
        try SMCKit.open()

        let forceCharging = try SMCKit.readData(SMCKey.disableCharging)
        let inhibitCharging = try SMCKit.readData(SMCKey.inhibitCharging)
        let lidClosed = try SMCKit.readData(SMCKey.lidClosed)
        let temperature = try SMCKit.temperature(.init(fromStaticString: "TB0T"))

        return SMCStatus(
            forceCharging: forceCharging.0 == 01,
            inhitbitCharging: inhibitCharging.0 == 01,
            lidClosed: lidClosed.0 == 01,
            batteryTemperature: temperature
        )
    }
}
