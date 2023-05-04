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

public protocol ServerDelegate: AnyObject {
    func thereIsNothingToDo()
}

public final class Server {
    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "🛟")
    private lazy var routeHandler = {
        let routeHandler = RouteHandler { [weak self] in
            self?.delegate?.thereIsNothingToDo()
        }
        return routeHandler
    }()
    public weak var delegate: ServerDelegate?

    public init() { }

    public func start() async throws {
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
            server.setErrorHandler(errorHandler)

            server.start()
        } catch {
            logger.error("Server error: \(error, privacy: .public)")
            throw error
        }
        try await Task.sleep(for: .seconds(2))
    }
}
