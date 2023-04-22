//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import SecureXPC

func chargingRouteHandler(_ message: SMCChargingCommand) throws {
    let code = FourCharCode(fromStaticString: "CH0B")
    let dataType = try SMCKit.keyInformation(code)
    NSLog("dataType \(dataType)")
    let key = SMCKey(
        code: code,
        info: dataType
    )
    var data = try SMCKit.readData(key)
    NSLog("data \(data)")
    switch message {
    case .enableCharging:
        data.0 = 00
    case .disableCharging:
        data.0 = 02
    }
    try SMCKit.writeData(key, data: data)
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

