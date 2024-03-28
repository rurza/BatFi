//
//  XPCClient.swift
//
//
//  Created by Adam Różyński on 26/03/2024.
//

import Dependencies
import Foundation
import os
import Shared
import SwiftyXPC

actor XPCClient {

    private var connection: XPCConnection
    private lazy var logger = Logger(category: "XPC Client")

    private init() {
        connection = Self.createConnection()
    }

    static let shared = XPCClient()

    func closeConnection() {
        connection.cancel()
    }

    func resetConnection() {
        connection.cancel()
        connection = Self.createConnection()
    }

    func sendMessage<Request: Codable>(_ route: XPCRoute, request: Request) async throws {
        do {
            try await withTimeout(seconds: 2) {
                try await self.connection.sendMessage(name: route.rawValue, request: request)
            }
        } catch {
            logger.error("Error while sending message: \(error). Route: \(route.rawValue)")
            throw error
        }
    }

    func sendMessage<Request: Codable, Response: Codable>(_ route: XPCRoute, request: Request) async throws -> Response {
        logger.debug("Sending message with route: \(route.rawValue))")
        return try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                try await self.connection.sendMessage(name: route.rawValue, request: request)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                await self.logger.error("Time out while sending message with route: \(route.rawValue)")
                throw TaskError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func sendMessage<Response: Codable>(_ route: XPCRoute) async throws -> Response {
        logger.debug("Sending message with route: \(route.rawValue)")
        return try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                try await self.connection.sendMessage(name: route.rawValue)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                await self.logger.error("Time out while sending message with route: \(route.rawValue)")
                throw TaskError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func sendMessage(_ route: XPCRoute) async throws  {
        logger.debug("Sending message with route: \(route.rawValue)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.connection.sendMessage(name: route.rawValue)
                await self.logger.debug("Message: \(route.rawValue) sent!")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                await self.logger.error("Time out while sending message with route: \(route.rawValue)")
                throw TaskError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    private static func createConnection() -> XPCConnection {
        let connection = try! XPCConnection(
            type: .remoteMachService(serviceName: Constant.helperBundleIdentifier, isPrivilegedHelperTool: true),
            codeSigningRequirement: xpcEntitlement
        )
        connection.activate()
        return connection
    }

}
