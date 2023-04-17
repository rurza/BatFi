//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import Foundation
import SecureXPC

NSLog("starting helper tool. PID \(getpid()). PPID \(getppid()).")

func runMessage(_ message: SMCCommand) throws -> Bool {
    NSLog("blah blah")
    return true
}

let server = try XPCServer.forMachService(withCriteria: .forDaemon(named: helperBundleIdentifier, withClientRequirement: .sameParentBundle))
server.registerRoute(XPCRoute.battery, handler: runMessage)
server.setErrorHandler { error in
    if case .connectionInvalid = error {
        // Ignore invalidated connections as this happens whenever the client disconnects which is not a problem
    } else {
        NSLog("error: \(error)")
    }
}
server.startAndBlock()
