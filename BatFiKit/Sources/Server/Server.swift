//
//  Server.swift
//
//
//  Created by Adam on 02/05/2023.
//

import EmbeddedPropertyList
import Foundation
import os
import SwiftyXPC
import Shared

public final class Server {
    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "🛟")
    private lazy var routeHandler = RouteHandler()


    public init() {}

    public func start() throws {
        let data = try EmbeddedPropertyListReader.info.readInternal()
        let plist = try PropertyListDecoder().decode(HelperPropertyList.self, from: data)
        logger.notice("Server version: \(plist.version, privacy: .public)")

        func errorHandler(_ connection: XPCConnection, _ error: Error) {
            logger.error("Server error. \(error, privacy: .public)")
        }

        do {
            let entitlement = plist.authorizedClients.first!
            var requirement: SecRequirement!
            var unmanagedError: Unmanaged<CFError>!

            let status = SecRequirementCreateWithStringAndErrors(
                entitlement as CFString,
                [],
                &unmanagedError,
                &requirement
            )

            if status != errSecSuccess {
                let error = unmanagedError.takeRetainedValue()
                logger.fault("Code signing requirement text, `\(xpcEntitlement)`, is not valid: \(error).")                
            }

            let listener = try XPCListener(type: .machService(name: Constant.helperBundleIdentifier), codeSigningRequirement: entitlement)
            listener.errorHandler = errorHandler

            listener.setMessageHandler(name: XPCRoute.charging.rawValue) { [weak self] (_, message: SMCChargingCommand) in
                self?.logger.notice("Received charging command.")
                try await self?.routeHandler.charging(message)
            }

            listener.setMessageHandler(name: XPCRoute.smcStatus.rawValue) { [weak self] (connection: XPCConnection) in
                self?.logger.notice("Received smcStatus command.")
                return try await self?.routeHandler.smcStatus()
            }

            listener.setMessageHandler(name: XPCRoute.magSafeLEDColor.rawValue, handler: { [weak self] (_, option: MagSafeLEDOption) in
                self?.logger.notice("Received MagSafe LED Color command.")
                return try await self?.routeHandler.magsafeLEDColor(option)
            })

            listener.setMessageHandler(name: XPCRoute.powerInfo.rawValue) { [weak self] _ in
                try self?.routeHandler.powerInfo()
            }

            listener.setMessageHandler(name: XPCRoute.quit.rawValue) { [weak self] _ in
                self?.logger.notice("Received quit command.")
                Task {
                    listener.cancel()
                    exit(0)
                }
            }

            listener.setMessageHandler(name: XPCRoute.ping.rawValue, handler: { _ in })

            listener.activate()

            logger.notice("Server launched!")
            RunLoop.main.run()
            logger.error("RunLoop exited.")
        } catch {
            logger.error("Server error: \(error, privacy: .public)")
            throw error
        }
    }
}
