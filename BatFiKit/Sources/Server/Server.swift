//
//  Server.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AsyncXPCConnection
import EmbeddedPropertyList
import Foundation
import os
import Shared

public final class Server {
    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "🛟")

    public init() {}

    public func start() throws {
        let data = try EmbeddedPropertyListReader.info.readInternal()
        let plist = try PropertyListDecoder().decode(HelperPropertyList.self, from: data)
        logger.notice("Server version: \(plist.version, privacy: .public)")
        let entitlement = plist.authorizedClients.first!
        var requirement: SecRequirement!
        var unmanagedError: Unmanaged<CFError>!

        let status = SecRequirementCreateWithStringAndErrors(
            entitlement as CFString,
            [],
            &unmanagedError,
            &requirement
        )

        if status != errSecSuccess {
            let error = unmanagedError.takeRetainedValue()
            logger.fault("Code signing requirement text, `\(xpcEntitlement)`, is not valid: \(error).")
        }

        let listener = NSXPCListener(machServiceName: Constant.helperBundleIdentifier)
        
        let delegate = ListenerDelegate()
        listener.delegate = delegate
        listener.resume()

        logger.notice("Server launched!")
        RunLoop.main.run()
        logger.error("RunLoop exited.")
    }
}
