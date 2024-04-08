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
import Sentry
import Shared

public final class Server {
    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "Server")

    public init() {}

    public func start() throws {
        let data = try EmbeddedPropertyListReader.info.readInternal()
        let plist = try PropertyListDecoder().decode(HelperPropertyList.self, from: data)
        logger.notice("Server version: \(plist.version, privacy: .public), build: \(plist.build, privacy: .public)")

        let listener = NSXPCListener(machServiceName: Constant.helperBundleIdentifier)
        let delegate = ListenerDelegate()
        listener.delegate = delegate
        listener.resume()

        if AppDefaults.userAllowsAnalytics {
            SentrySDK.start { options in
                options.dsn = "https://858e7a160cc0add058de86a8fcd489c8@o4506988322357248.ingest.us.sentry.io/4506988323799040"
                #if DEBUG
                options.debug = true
                #endif

                options.tracesSampleRate = 1.0
                options.diagnosticLevel = .warning

                options.releaseName = "BatFiHelper@\(plist.version)@\(plist.build)"
            }
        }

        logger.notice("Server launched!")
        RunLoop.main.run()
        logger.error("RunLoop exited.")
    }
}
