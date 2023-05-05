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
    private var timer: Timer?

    private lazy var routeHandler = makeRouteHandler()
    public weak var delegate: ServerDelegate?

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
            server.setErrorHandler(errorHandler)

            server.start()
            RunLoop.main.run()
            logger.error("RunLoop exited.")
        } catch {
            logger.error("Server error: \(error, privacy: .public)")
            throw error
        }
    }

    private func makeRouteHandler() -> RouteHandler {
        RouteHandler { [weak self] in
            self?.setUpTimer()
        }
    }

    private func setUpTimer() {
        Task { @MainActor in
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
                self?.logger.notice("There is nothing to do.")
                self?.delegate?.thereIsNothingToDo()
            }
        }
    }
}
