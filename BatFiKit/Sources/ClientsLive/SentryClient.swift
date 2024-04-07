//
//  SentryClient.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Clients
import Dependencies
import Sentry

extension Clients.SentryClient: DependencyKey {
    public static var liveValue: Self = {
        Clients.SentryClient(
            startSDK: {
                SentrySDK.start { options in
                    options.dsn = "https://858e7a160cc0add058de86a8fcd489c8@o4506988322357248.ingest.us.sentry.io/4506988323799040"
                    #if DEBUG
                    options.debug = true
                    #endif

                    options.tracesSampleRate = 1.0
                    options.diagnosticLevel = .warning
                    options.enableMetricKit = true
                }
            },
            captureMessage: { message in
                SentrySDK.capture(message: message)
            },
            captureError: { error in
                SentrySDK.capture(error: error)
            }
        )
    }()
}
