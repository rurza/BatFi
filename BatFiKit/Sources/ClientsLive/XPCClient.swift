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

enum XPCClientError: Error {
    case canNotGetPowerMode
}

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

    func currentMagSafeLEDOption() async throws -> MagSafeLEDOption {
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.getMagSafeLEDOption { rawValue, error in
                if let option = MagSafeLEDOption(rawValue: rawValue) {
                    continuation.resume(returning: option)
                } else if let error {
                    self.logger.error("Error when getting MagSafe LED color: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                } else {
                    assertionFailure("Shouldn't happen. Both option and error are nil.")
                }
            }
        }
    }

    func pingHelper() async throws -> Bool {
        logger.debug("Pinging helper")
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.ping { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    func quitHelper() async throws -> Bool {
        logger.debug("Quitting helper")
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.quit { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    func setPowerMode(_ mode: UInt8) async throws {
        logger.debug("Setting power mode: \(mode)")
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.turnPowerMode(mode) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func getPowerMode() async throws -> (UInt8, Bool) {
        logger.debug("Getting power mode")
        let remote = newRemoteService()
        return try await remote.withContinuation { service, continuation in
            service.currentPowerMode { mode, highPowerModeIsAvailable in
                if let uint = mode?.uint8Value {
                    continuation.resume(returning: (uint, highPowerModeIsAvailable))
                } else {
                    continuation.resume(throwing: XPCClientError.canNotGetPowerMode)
                }
            }
        }
    }


    // MARK: - Private

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
        connection.setCodeSigningRequirement(xpcEntitlement)
        connection.resume()
        return connection
    }
    
    private func newConnectionWithInterface() -> NSXPCConnection {
        let connection = newConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: XPCService.self)
        return connection
    }
}
