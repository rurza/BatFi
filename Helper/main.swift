//
//  main.swift
//  Helper
//
//  Created by Adam on 16/04/2023.
//

import EmbeddedPropertyList
import Foundation
import SecureXPC
import os

let logger = Logger(subsystem: helperBundleIdentifier, category: "🛟")

do {
    let data = try EmbeddedPropertyListReader.info.readInternal()
    let plist = try PropertyListDecoder().decode(HelperPropertyList.self, from: data)
    logger.notice("Helper version: \(plist.bundleIdentifier, privacy: .public)")
} catch {
    logger.error("Embeded plist error: \(error, privacy: .public)")
}

func errorHandler(_ error: XPCError) async {
    logger.error("Server error. \(error, privacy: .public)")
    logger.notice("Quitting...")
    exit(0)
}
do {
    let server = try XPCServer.forMachService(withCriteria: .forDaemon(withClientRequirement: try .sameParentBundle))
    server.registerRoute(XPCRoute.charging, handler: RouteHandler.charging)
    server.registerRoute(XPCRoute.smcStatus, handler: RouteHandler.smcStatus)
    server.setErrorHandler(errorHandler)

    logger.notice("Server is about to start.")
    server.start()
    try await Task.sleep(for: .seconds(5))
    logger.notice("Time to exit. Bye!")
    exit(0)
} catch {
    logger.error("Shoot! We have an error: \(error, privacy: .public)")
}

