//
//  Server.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import EmbeddedPropertyList
import Foundation
import os
import SecureXPC
import Shared

public final class Server {
    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "🛟")
    private lazy var routeHandler = RouteHandler()

    public init() { }

    public func start() throws {
        do {
            let data = try EmbeddedPropertyListReader.info.readInternal()
            let plist = try PropertyListDecoder().decode(HelperPropertyList.self, from: data)
            logger.notice("Server version: \(plist.bundleIdentifier, privacy: .public)")
        } catch {
            logger.error("Embeded plist error: \(error, privacy: .public)")
        }

        func errorHandler(_ error: XPCError) async {
            logger.error("Server error. \(error, privacy: .public)")
        }

        do {
            let server = try XPCServer.forMachService()
            server.registerRoute(XPCRoute.charging, handler: routeHandler.charging)
            server.registerRoute(XPCRoute.smcStatus, handler: routeHandler.smcStatus)
            server.registerRoute(
                XPCRoute.quit,
                handler: { [weak self] in
                    self?.logger.notice("Received quit command.")
                    Task {
                        try await Task.sleep(for: .seconds(1))
                        exit(0)
                    }
                }
            )
            server.registerRoute(XPCRoute.magSafeLEDColor, handler: routeHandler.magsafeLEDColor)
            server.registerRoute(XPCRoute.powerSettingOption, handler: routeHandler.powerSettingOption)
            server.setErrorHandler(errorHandler)

            server.start()
            logger.notice("Server launched!")
            RunLoop.main.run()
            logger.error("RunLoop exited.")
        } catch {
            logger.error("Server error: \(error, privacy: .public)")
            throw error
        }
    }
}
