//
//  XPCClient.swift
//
//
//  Created by Adam Różyński on 26/03/2024.
//

import AsyncXPCConnection
import Dependencies
import Foundation
import os
import Shared

actor XPCClient {
    private lazy var logger = Logger(category: "XPC Client")

    private init() { }

    static let shared = XPCClient()

    func changeChargingMode(_ newMode: SMCChargingCommand) async throws {
        switch newMode {
        case .forceDischarging:
            try await setChargingMode(XPCService.setForceDischarge)
        case .auto:
            try await setChargingMode(XPCService.setAutocharge)
        case .inhibitCharging:
            try await setChargingMode(XPCService.setInhibitCharge)
        case .enableSystemChargeLimit:
            try await setChargingMode(XPCService.setEnableSystemChargeLimit)
        }
    }

    func getPowerDistribution() async throws -> PowerDistributionInfo {
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.getPowerDistribution { powerInfo, error in
                if let powerInfo {
                    continuation.resume(returning: powerInfo)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both PowerDistributionInfo and error are nil.")
                }
            }
        }
    }

    func quitHelper() async throws {
        logger.debug("Quitting helper")
        let remote = newRemoteService()
        try await remote.withService { service in
            service.quit()
            self.logger.debug("Helper quit")
        }
    }

    func getSMCChargingStatus() async throws -> SMCChargingStatus {
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.getCurrentChargingStatus { status, error in
                if let status {
                    continuation.resume(returning: status)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both status and error are nil.")
                }
            }
        }
    }

    func changeMagSafeLEDColor(_ color: MagSafeLEDOption) async throws -> MagSafeLEDOption {
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.setMagSafeLEDColor(color: color.rawValue) { rawValue, error in
                if let option = MagSafeLEDOption(rawValue: rawValue) {
                    continuation.resume(returning: option)
                } else if let error {
                    self.logger.error("Error when setting MagSafe LED color: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both option and error are nil.")
                }
            }
        }
    }

    private func setChargingMode(
        _ handler: (XPCService) -> (@escaping (Error?) -> Void) -> Void
    ) async throws {
        let service = newRemoteService()
        try await service.withContinuation { (service, continuation: CheckedContinuation<Void, Error>) in
            handler(service)() { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func newRemoteService() -> RemoteXPCService<XPCService> {
        RemoteXPCService(connection: newConnection(), remoteInterface: XPCService.self)
    }


    private func newConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: Constant.helperBundleIdentifier,
            options: .privileged
        )
        connection.resume()
        return connection
    }

    private func newConnectionWithInterface() -> NSXPCConnection {
        let connection = newConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: XPCService.self)
        return connection
    }
}

enum XPCRoute {
    case charging(SMCChargingCommand)
    case magSafeLEDColor(MagSafeLEDOption)
    case ping
    case powerInfo
    case quit
    case smcStatus
}

