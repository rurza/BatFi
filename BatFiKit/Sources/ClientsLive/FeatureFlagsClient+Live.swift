//
//  FeatureFlagsClient.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import Clients
import Dependencies
import Shared

extension FeatureFlagsClient: DependencyKey {
    nonisolated(unsafe) public static var liveValue: FeatureFlagsClient = {
        nonisolated(unsafe) let enabledFeatureFlags = EnabledFeatureFlags()
        return Self(
            enableFeatureFlag: { flag in
                enabledFeatureFlags.enableFeature(flag)
            },
            isUsingBetaVersion: {
                enabledFeatureFlags.enabledlyFeatures.contains(.beta)
            }
        )
    }()
}
