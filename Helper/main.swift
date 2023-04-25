//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import SecureXPC

let server = try XPCServer.forMachService()
server.registerRoute(XPCRoute.charging, handler: RouteHandler.charging)
server.registerRoute(XPCRoute.smcStatus, handler: RouteHandler.smcStatus)
server.setErrorHandler { error in
    if case .connectionInvalid = error {
        // Ignore invalidated connections as this happens whenever the client disconnects which is not a problem
    } else {
        NSLog("error: \(error)")
    }
}
server.startAndBlock()

