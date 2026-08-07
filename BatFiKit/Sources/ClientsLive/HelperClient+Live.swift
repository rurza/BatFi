//
//  HelperClient.swift
//
//
//  Created by Adam on 16/05/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation
import os
@preconcurrency import ServiceManagement
import Shared

extension HelperClient: DependencyKey {
    public static let liveValue: HelperClient = {
        nonisolated(unsafe) let service = SMAppService.daemon(plistName: Constant.helperPlistName)
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
                let status = await installer.service.status
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
                } // always return a status, even if it's a duplicate, otherwise onboarding won't work
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
            },
            helperOwnership: {
                // Read once per call rather than cached: the app can be moved on disk while
                // it runs, and a cached "expected path" would then accuse the correct helper.
                let expectedURL = HelperCodeIdentityInspector.expectedHelperExecutableURL
                let bundled = HelperCodeIdentityInspector.identity(ofFileAt: expectedURL)
                do {
                    let pid = try await XPCClient.shared.helperProcessIdentifier()
                    let running = HelperCodeIdentityInspector.identity(
                        ofProcessWithID: pid,
                        satisfying: xpcEntitlement
                    )
                    let ownership = HelperOwnershipCheck.evaluate(
                        running: running,
                        expectedExecutablePath: expectedURL.path,
                        expectedCDHash: bundled?.cdHash
                    )
                    switch ownership {
                    case .ours:
                        logger.notice("The running helper belongs to this copy of BatFi")
                    case let .foreign(conflict):
                        logger.error("The running helper is not ours (\(String(describing: conflict.kind), privacy: .public)). Running: \(conflict.runningExecutablePath, privacy: .public). Expected: \(conflict.expectedExecutablePath, privacy: .public)")
                    case let .undetermined(reason):
                        logger.warning("Helper ownership undetermined: \(reason, privacy: .public)")
                    }
                    return ownership
                } catch {
                    // Unreachable, not foreign. Saying so keeps the ownership recovery — which
                    // costs the user an approval — off a failure the reachability path owns.
                    logger.warning("Could not identify the helper: \(error.localizedDescription, privacy: .public)")
                    return .undetermined(error.localizedDescription)
                }
            }
        )
        return manager
    }()
}

extension SMAppService.Status: @retroactive CustomStringConvertible {
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
