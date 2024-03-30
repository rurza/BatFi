//
//  HelperClient.swift
//
//
//  Created by Adam on 16/05/2023.
//

import Clients
import Dependencies
import Foundation
import os
import ServiceManagement
import Shared

extension HelperClient: DependencyKey {
    public static let liveValue: HelperClient = {
        let service = SMAppService.daemon(plistName: Constant.helperPlistName)
        let installer = HelperInstaller(service: service)
        let logger = Logger(category: "Helper Client")
        let manager = HelperClient(
            installHelper: {
                do {
                    logger.notice("Installing daemon...")
                    try await installer.registerService()
                    logger.notice("Daemon installed succesfully")
                } catch {
                    logger.error("Daemon registering error: \(error, privacy: .public)")
                    throw error
                }
            },
            removeHelper: {
                do {
                    logger.notice("Removing daemon...")
                    try await installer.unregisterService()
                    logger.notice("Daemon removed")
                } catch {
                    logger.error("Daemon removal error: \(error, privacy: .public)")
                    throw error
                }
            },
            helperStatus: {
                logger.notice("Checking helper status...")
                let status = installer.service.status
                logger.notice("Helper status: \(status, privacy: .public)")
                return status
            },
            observeHelperStatus: {
                AsyncStream<SMAppService.Status> { continuation in
                    let task = Task {
                        for await _ in SuspendingClock().timer(interval: .milliseconds(1500)) {
                            continuation.yield(service.status)
                        }
                    }
                    continuation.yield(service.status)
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
                .removeDuplicates()
                .eraseToStream()
            },
            quitHelper: {
                logger.debug("Should quit the helper")
                do {
                    _ = try await XPCClient.shared.quitHelper()
                } catch {
                    logger.warning("Helper could failed to quit: \(error.localizedDescription, privacy: .public)")
                }
            },
            pingHelper: {
                return try await XPCClient.shared.pingHelper()
            }
        )
        return manager
    }()
}

extension SMAppService.Status: CustomStringConvertible {
    public var description: String {
        switch self {
        case .enabled:
            return "enabled"
        case .notFound:
            return "Error. Not found"
        case .notRegistered:
            return "not registered"
        case .requiresApproval:
            return "requires approval"
        @unknown default:
            return "unknown"
        }
    }
}

private actor HelperInstaller {
    let service: SMAppService

    init(service: SMAppService) {
        self.service = service
    }

    func registerService() throws {
        try service.register()
    }

    func unregisterService() async throws {
        try await service.unregister()
    }
}
