//
//  Helper.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import EmbeddedPropertyList
import Foundation
import os
import SecureXPC
import Shared

public final class Helper {
    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "🛟")

    public init() { }

    public func start() async throws {
        do {
            let data = try EmbeddedPropertyListReader.info.readInternal()
            let plist = try PropertyListDecoder().decode(HelperPropertyList.self, from: data)
            logger.notice("Helper version: \(plist.bundleIdentifier, privacy: .public)")
        } catch {
            logger.error("Embeded plist error: \(error, privacy: .public)")
        }

        func errorHandler(_ error: XPCError) async {
            logger.error("Server error. \(error, privacy: .public)")
        }

        do {
            let server = try XPCServer.forMachService()
            server.registerRoute(XPCRoute.charging, handler: RouteHandler.charging)
            server.registerRoute(XPCRoute.smcStatus, handler: RouteHandler.smcStatus)
            server.setErrorHandler(errorHandler)

            server.start()
            try await Task.sleep(for: .seconds(5))
        } catch {
            logger.error("Server error: \(error, privacy: .public)")
            throw error
        }
    }
}
