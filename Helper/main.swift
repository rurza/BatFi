//
//  main.swift
//  BatFi Helper
//
//  Created by Adam on 13/04/2023.
//

import Foundation
import SecureXPC

NSLog("starting helper tool. PID \(getpid()). PPID \(getppid()).")

do {
    let server = try XPCServer.forMachService()
    server.registerRoute(XPCRoute.uninstall, handler: uninstall)
    server.startAndBlock()
} catch {

}

private func uninstall() {

}

