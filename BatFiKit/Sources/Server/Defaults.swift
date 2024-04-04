//
//  Defaults.swift
//
//
//  Created by Adam Różyński on 04/04/2024.
//

import Defaults
import DefaultsKeys
import Foundation
import Shared

final class AppDefaults {
    static var userAllowsAnalytics: Bool {
        let defaults = UserDefaults(suiteName: Constant.appBundleIdentifier)!
        return defaults[.sendAnalytics]
    }
}
