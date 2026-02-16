//
//  FeatureFlagsClient.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import Dependencies
import DependenciesMacros
import Shared

@DependencyClient
public struct FeatureFlagsClient: Sendable {
    public var enableFeatureFlag: @Sendable (_ featureFlag: FeatureFlag) -> Void
    public var isUsingBetaVersion: @Sendable () -> Bool = { false }
}

extension FeatureFlagsClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: FeatureFlagsClient = .init()
}

public extension DependencyValues {
    var featureFlags: FeatureFlagsClient {
        get { self[FeatureFlagsClient.self] }
        set { self[FeatureFlagsClient.self] = newValue }
    }
}
