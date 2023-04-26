//
//  HelperManager.swift
//  BatFi
//
//  Created by Adam on 22/04/2023.
//

import os
import Foundation
import ServiceManagement

final class HelperManager {
    lazy var service = SMAppService.daemon(plistName: helperPlistName)
    static let shared = HelperManager()
    private lazy var logger = Logger(category: "👹")

    func registerServiceIfNeeded() throws {
        if service.status == .notRegistered {
            try registerService()
        }
    }

    func registerService() throws {
        Task {
            logger.log(level: .debug, "Installing daemon...")
            do {
                try service.register()
            } catch {
                logger.error("Daemon registering error: \(error, privacy: .public)")
                throw error
            }
            logger.log(level: .debug, "Daemon installed succesfully")
        }
    }

    func removeService() throws {
        Task {
            logger.log(level: .debug, "Removing daemon...")
            do {
                try await service.unregister()
            } catch {
                logger.error("Daemon removal error: \(error, privacy: .public)")
            }
            logger.log(level: .debug, "Daemon removed")
        }
    }
}

