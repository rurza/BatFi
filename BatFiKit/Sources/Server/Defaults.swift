//
//  Defaults.swift
//
//
//  Created by Adam Różyński on 04/04/2024.
//

import Foundation
import Shared

final class AppDefaults {
    static func shouldStartCrashReporting(isBeta: Bool) -> Bool {
        let defaults = UserDefaults(suiteName: Constant.appBundleIdentifier)!
        return AnalyticsPreference.shouldStartCrashReporting(isBeta: isBeta, defaults: defaults)
    }
}
