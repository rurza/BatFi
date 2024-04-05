//
//  FeatureFlags.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import Foundation

public enum FeatureFlag {
    case beta
}

public final class EnabledFeatureFlags {
    public private(set) var enabledlyFeatures: Set<FeatureFlag> = []

    public init() { }

    public func enableFeature(_ feature: FeatureFlag) {
        enabledlyFeatures.insert(feature)
    }

    public func disableFeature(_ feature: FeatureFlag) {
        enabledlyFeatures.remove(feature)
    }
}
