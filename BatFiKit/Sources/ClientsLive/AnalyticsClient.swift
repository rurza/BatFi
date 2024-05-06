//
//  AnalyticsClient.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Clients
import Dependencies
import Sentry

extension Clients.AnalyticsClient: DependencyKey {
    public static var liveValue: Self = {
        let state = AnalyticsState()
        return Clients.AnalyticsClient(
            startSDK: {
                guard await !state.isEnabled else { return }
                SentrySDK.start { options in
                    options.dsn = analyticsDSN
                    #if DEBUG
                    options.debug = true
                    #endif

                    let releaseVersionNumber = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
                    let buildVersionNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

                    options.tracesSampleRate = 1.0
                    options.diagnosticLevel = .warning
                    options.enableMetricKit = true
                    options.enableAppHangTracking = false
                    options.releaseName = "BatFi@\(releaseVersionNumber ?? "Unknown")@\(buildVersionNumber ?? "Unknown")"
                }
                await state.enableAnalytics()
            },
            captureMessage: { message in
                if await state.isEnabled {
                    SentrySDK.capture(message: message)
                }
            },
            captureError: { error in
                if await state.isEnabled {
                    SentrySDK.capture(error: error)
                }
            },
            addBreadcrumb: { category, message in
                if await state.isEnabled {
                    let breadcrumb = Breadcrumb(level: .info, category: category.rawValue)
                    breadcrumb.message = message
                    SentrySDK.addBreadcrumb(breadcrumb)
                }
            },
            closeSDK: {
                await state.disableAnalytics()
                SentrySDK.close()
            }
        )
    }()
}

private actor AnalyticsState {
    var isEnabled = false

    func enableAnalytics() {
        isEnabled = true
    }

    func disableAnalytics() {
        isEnabled = false
    }
}
