//
//  SettingsDefaultsClient.swift
//  
//
//  Created by Adam on 18/05/2023.
//

import AsyncAlgorithms
import Clients
import Dependencies
import Defaults
import DefaultsKeys
import os
import Shared

extension SettingsDefaultsClient: DependencyKey {
    public static let liveValue: SettingsDefaultsClient = {
        let logger = Logger(category: "👀🔧📚")
        func asyncStreamForKey<Value>(_ key: Defaults.Keys.Key<Value>) -> AsyncStream<Value> where Value: CustomStringConvertible & Equatable {
            Defaults.updates(key).removeDuplicates().map {
                logger.debug("\(key.name) did change: \($0.description)")
                return $0
            }.eraseToStream()
        }
        let client = SettingsDefaultsClient(
            showBatteryPercentage: { newValue in
                if let newValue {
                    Defaults[.showBatteryPercentageInStatusIcon] = newValue
                }
                return Defaults[.showBatteryPercentageInStatusIcon]
            },
            observeShowBatteryPercentage: {
                asyncStreamForKey(.showBatteryPercentageInStatusIcon)
            },
            showMonochromeIcon: { newValue in
                if let newValue {
                    Defaults[.monochromeStatusIcon] = newValue
                }
                return Defaults[.monochromeStatusIcon]
            },
            observeShowMonochromeIcon: {
                asyncStreamForKey(.monochromeStatusIcon)
            },
            launchAtLogin: { newValue in
                if let newValue {
                    Defaults[.launchAtLogin] = newValue
                }
                return Defaults[.launchAtLogin]
            },
            onboardingIsDone: { newValue in
                if let newValue {
                    Defaults[.onboardingIsDone] = newValue
                }
                return Defaults[.onboardingIsDone]
            }
        )
        return client
    }()
}
