//
//  HelperManager.swift
//  
//
//  Created by Adam on 16/05/2023.
//

import Clients
import Foundation
import Dependencies
import os
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
                    logger.log(level: .debug, "Installing daemon...")
                    try await installer.registerService()
                    logger.log(level: .debug, "Daemon installed succesfully")
                } catch {
                    logger.error("Daemon registering error: \(error, privacy: .public)")
                    throw error
                }
            },
            removeHelper: {
                do {
                    logger.log(level: .debug, "Removing daemon...")
                    try await installer.unregisterService()
                    logger.log(level: .debug, "Daemon removed")
                } catch {
                    logger.error("Daemon removal error: \(error, privacy: .public)")
                    throw error
                }
            },
            helperStatus: { await installer.service.status },
            observeHelperStatus: {
                return AsyncStream<SMAppService.Status> { continuation in
                    let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        continuation.yield(service.status)
                    }
                    continuation.yield(service.status)
                    continuation.onTermination = { _ in
                        timer.invalidate()
                    }
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
