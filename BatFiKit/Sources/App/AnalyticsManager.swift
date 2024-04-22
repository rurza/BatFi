//
//  AnalyticsManager.swift
//
//
//  Created by Adam Różyński on 21/04/2024.
//

import Dependencies
import Clients

final class AnalyticsManager {
    @Dependency(\.defaults) private var defaults
    @Dependency(\.analyticsClient) private var analyticsClient
    private var analyticsEnabled = false

    func start(shouldEnable: Bool) {
        startAnalyticsIfNeeded(shouldEnable)
        setUpObserving()
    }

    private func startAnalyticsIfNeeded(_ start: Bool) {
        if start {
            Task {
                await enableAnalytics()
            }
        }
    }

    private func setUpObserving() {
        Task {
            for await enable in defaults.observe(.sendAnalytics) {
                if enable {
                    await enableAnalytics()
                } else  {
                    await analyticsClient.closeSDK()
                    analyticsEnabled = false
                }
            }
        }
    }

    private func enableAnalytics() async {
        await analyticsClient.startSDK()
        analyticsEnabled = true
    }
}
