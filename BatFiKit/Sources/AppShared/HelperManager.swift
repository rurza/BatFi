//
//  HelperManager.swift
//  BatFi
//
//  Created by Adam on 22/04/2023.
//

import Foundation
import os
import ServiceManagement
import Shared

public final class HelperManager {
    lazy var service = SMAppService.daemon(plistName: Constant.helperPlistName)
    public static let shared = HelperManager()
    private lazy var logger = Logger(category: "👹")
    
    public init() { }

    public func registerService() throws {
        logger.log(level: .debug, "Installing daemon...")
        do {
            try service.register()
            logger.log(level: .debug, "Daemon installed succesfully")
        } catch {
            logger.error("Daemon registering error: \(error, privacy: .public)")
            throw error
        }
    }

    public func removeService() throws {
        logger.log(level: .debug, "Removing daemon...")
        do {
            try service.unregister()
            logger.log(level: .debug, "Daemon removed")
        } catch {
            logger.error("Daemon removal error: \(error, privacy: .public)")
        }
    }
}

