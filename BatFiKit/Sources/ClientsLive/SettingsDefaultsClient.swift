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

extension SettingsDefaultsClient: DependencyKey {
    public static let liveValue: SettingsDefaultsClient = {
        let client = SettingsDefaultsClient(
            showBatteryPercentage: { newValue in
                if let newValue {
                    Defaults[.showBatteryPercentageInStatusIcon] = newValue
                }
                return Defaults[.showBatteryPercentageInStatusIcon]
            },
            observeShowBatteryPercentage: {
                Defaults.updates(.showBatteryPercentageInStatusIcon).removeDuplicates().eraseToStream()
            },
            showMonochromeIcon: { newValue in
                if let newValue {
                    Defaults[.monochromeStatusIcon] = newValue
                }
                return Defaults[.monochromeStatusIcon]
            },
            observeShowMonochromeIcon: {
                Defaults.updates(.monochromeStatusIcon).removeDuplicates().eraseToStream()
            }
        )
        return client
    }()
}
