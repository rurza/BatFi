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
public struct FeatureFlagsClient {
    public var enableFeatureFlag: (_ featureFlag: FeatureFlag) -> Void
    public var isUsingBetaVersion: () -> Bool = { false }
}

extension FeatureFlagsClient: TestDependencyKey {
    public static var testValue: FeatureFlagsClient = .init()
}

public extension DependencyValues {
    var featureFlags: FeatureFlagsClient {
        get { self[FeatureFlagsClient.self] }
        set { self[FeatureFlagsClient.self] = newValue }
    }
}
