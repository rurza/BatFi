//
//  HelperManager.swift
//
//
//  Created by Adam on 16/05/2023.
//

import Clients
import Dependencies
import Foundation
import os
import SecureXPC
import ServiceManagement
import Shared

extension HelperManager: DependencyKey {
    public static let liveValue: HelperManager = {
        let service = SMAppService.daemon(plistName: Constant.helperPlistName)
        let installer = HelperInstaller(service: service)
        let logger = Logger(category: "👹")
        let manager = HelperManager(
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
            helperStatus: { installer.service.status },
            observeHelperStatus: {
                AsyncStream<SMAppService.Status> { continuation in
                    let task = Task {
                        for await _ in SuspendingClock().timer(interval: .milliseconds(500)) {
                            continuation.yield(service.status)
                        }
                    }
                    continuation.yield(service.status)
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            },
            quitHelper: {
                logger.debug("Should quit the helper")
                do {
                    let client = XPCClient.forMachService(
                        named: Constant.helperBundleIdentifier,
                        withServerRequirement: try! .sameTeamIdentifier
                    )
                    try await client.send(to: XPCRoute.quit)
                    logger.notice("Helper did quit")
                } catch {
                    logger.warning("Helper could failed to quit: \(error.localizedDescription, privacy: .public)")
                }
            }
        )
        return manager
    }()
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
