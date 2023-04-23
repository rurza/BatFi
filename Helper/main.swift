//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import SecureXPC

func chargingRouteHandler(_ message: SMCChargingCommand) throws {
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

let server = try XPCServer.forMachService()
server.registerRoute(XPCRoute.charging, handler: chargingRouteHandler)
server.setErrorHandler { error in
    if case .connectionInvalid = error {
        // Ignore invalidated connections as this happens whenever the client disconnects which is not a problem
    } else {
        NSLog("error: \(error)")
    }
}
server.startAndBlock()

