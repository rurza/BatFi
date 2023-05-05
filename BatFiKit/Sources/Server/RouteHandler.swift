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
    let handler: () -> Void
    private lazy var queue = DispatchQueue(label: "Timer", qos: .background)
    private var timerSource: DispatchSourceTimer?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func charging(_ message: SMCChargingCommand) async throws {
        defer {
            SMCKit.close()
            handler()
        }
        try SMCKit.open()

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
            throw error
        }
    }

    func smcStatus(_ message: SMCStatusCommand) async throws -> SMCStatus {
        defer {
            SMCKit.close()
            handler()
        }
        try SMCKit.open()

        switch message {
        case .status:
            let forceCharging = try SMCKit.readData(SMCKey.disableCharging)
            let inhibitChargingC = try SMCKit.readData(SMCKey.inhibitChargingC)
            let inhibitChargingB = try SMCKit.readData(SMCKey.inhibitChargingB)
            let lidClosed = try SMCKit.readData(SMCKey.lidClosed)

            logger.notice("Checking SMC status")

            return SMCStatus(
                forceCharging: forceCharging.0 == 01,
                inhitbitCharging: (inhibitChargingC.0 == 02 && inhibitChargingB.0 == 02)
                || (inhibitChargingC.0 == 03 && inhibitChargingB.0 == 03),
                lidClosed: lidClosed.0 == 01
            )
        }
    }
}
