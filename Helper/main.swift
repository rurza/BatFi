//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import SecureXPC


func chargingRouteHandler(_ message: SMCChargingCommand) throws -> Bool {
    NSLog("running message: \(message)")
    return true
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
try SMCKit.open()
server.startAndBlock()

