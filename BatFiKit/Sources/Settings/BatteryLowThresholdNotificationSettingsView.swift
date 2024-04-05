//
//  BatteryLowThresholdNotificationSettingsView.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import Defaults
import DefaultsKeys
import L10n
import SettingsKit
import SwiftUI

struct BatteryLowThresholdNotificationSettingsView: View {
    // high energy
    @Default(.batteryLowNotificationThreshold) private var batteryLowNotificationThreshold

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: 340) {
            Section(bottomDivider: true, label: {
                EmptyView()
            }, content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.Label.batteryLowThreshold(batteryLowNotificationThreshold))
                    SettingsSliderContainer(
                        minLabel: "5%",
                        maxLabel: "30%",
                        min: 5,
                        max: 30,
                        step: 5,
                        value: .convert(from: $batteryLowNotificationThreshold)
                    )
                }
            })
        }
    }
}
