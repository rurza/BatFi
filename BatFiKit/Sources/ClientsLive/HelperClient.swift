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
import SwiftyXPC
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
                    await XPCClient.shared.resetConnection()
                    logger.notice("Daemon installed succesfully")
                } catch {
                    logger.error("Daemon registering error: \(error, privacy: .public)")
                    throw error
                }
            },
            removeHelper: {
                do {
                    logger.notice("Removing daemon...")
                    await XPCClient.shared.closeConnection()
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
                    try await XPCClient.shared.sendMessage(.quit)
                    logger.notice("Helper did quit")
                } catch {
                    logger.warning("Helper could failed to quit: \(error.localizedDescription, privacy: .public)")
                }
            },
            pingHelper: {
                try await XPCClient.shared.sendMessage(.ping)
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