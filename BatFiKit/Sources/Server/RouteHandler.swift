//
//  RouteHandler.swift
//  Helper
//
//  Created by Adam on 25/04/2023.
//

import Foundation
import Shared

final class RouteHandler {
    static func charging(_ message: SMCChargingCommand) async throws {
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
            inhibitChargingByte = 02
        }

        try SMCKit.writeData(.disableCharging, uint8: disableChargingByte)
        try SMCKit.writeData(.inhibitChargingC, uint8: inhibitChargingByte)
        try SMCKit.writeData(.inhibitChargingB, uint8: inhibitChargingByte)
    }

    static func smcStatus(_ message: SMCStatusCommand) async throws -> SMCStatus {
        defer { SMCKit.close() }
        try SMCKit.open()

        switch message {
        case .status:
            let forceCharging = try SMCKit.readData(SMCKey.disableCharging)
            let inhibitChargingC = try SMCKit.readData(SMCKey.inhibitChargingC)
            let inhibitChargingB = try SMCKit.readData(SMCKey.inhibitChargingB)
            let lidClosed = try SMCKit.readData(SMCKey.lidClosed)

            return SMCStatus(
                forceCharging: forceCharging.0 == 01,
                inhitbitCharging: (inhibitChargingC.0 == 02 && inhibitChargingB.0 == 02)
                || (inhibitChargingC.0 == 03 && inhibitChargingB.0 == 03),
                lidClosed: lidClosed.0 == 01
            )
        }
    }
}
