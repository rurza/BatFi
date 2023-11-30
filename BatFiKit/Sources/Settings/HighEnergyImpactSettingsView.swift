//
//  HighEnergyImpactSettingsView.swift
//  
//
//  Created by Adam on 04/11/2023.
//

import Defaults
import DefaultsKeys
import L10n
import SettingsKit
import SwiftUI

struct HighEnergyImpactSettingsView: View {
    // high energy
    @Default(.highEnergyImpactProcessesThreshold)         private var highEnergyImpactProcessesThreshold
    @Default(.highEnergyImpactProcessesDuration)          private var highEnergyImpactProcessesDuration
    @Default(.highEnergyImpactProcessesCapacity)          private var highEnergyImpactProcessesCapacity

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: 340) {
            Section(bottomDivider: true, label: {
                EmptyView()
            }, content: {
                VStack(alignment: .leading, spacing: 2) {
                    let min = 200.0
                    let max = 800.0
                    Text(l10n.Label.highEnergyImpactProcessesThreshold(highEnergyImpactProcessesThreshold))
                    HighEnergyUsageSlider(
                        minLabel: "\(Int(min))",
                        maxLabel: "\(Int(max))",
                        min: min,
                        max: max,
                        step: 100,
                        value: .convert(from: $highEnergyImpactProcessesThreshold)
                    )
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 2) {
                    let duration = Duration.seconds(highEnergyImpactProcessesDuration)
                    let style = Duration.UnitsFormatStyle(allowedUnits: [.minutes], width: .wide)
                    Text(l10n.Label.highEnergyImpactProcessesDuration(duration.formatted(style))) 
                    let min = 60.0
                    let max = 300.0
                    let minDuration = Duration.seconds(min)
                    let maxDuration = Duration.seconds(max)
                    HighEnergyUsageSlider(
                        minLabel: minDuration.formatted(style),
                        maxLabel: maxDuration.formatted(style),
                        min: min,
                        max: max,
                        step: min,
                        value: $highEnergyImpactProcessesDuration
                    )
                }
                .padding(.bottom, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.Label.highEnergyImpactProcessesCapacity(highEnergyImpactProcessesCapacity))
                    HighEnergyUsageSlider(
                        minLabel: "2",
                        maxLabel: "8",
                        min: 2,
                        max: 8,
                        step: 1,
                        value: .convert(from: $highEnergyImpactProcessesCapacity)
                    )
                }
            })
        }
    }
}

private struct HighEnergyUsageSlider<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let minLabel: String
    let maxLabel: String
    let min: Value
    let max: Value
    let step: Value.Stride
    @Binding var value: Value

    var body: some View {
        VStack(spacing: 0) {
            Slider(value: $value, in: min...max, step: step)
            HStack {
                Text(minLabel)
                    .multilineTextAlignment(.leading)
                Spacer()
                Text(maxLabel)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
