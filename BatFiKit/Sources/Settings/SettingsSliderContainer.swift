//
//  SettingsSliderContainer.swift
//
//
//  Created by Adam Różyński on 05/04/2024.
//

import SwiftUI

struct SettingsSliderContainer<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    let minLabel: String
    let maxLabel: String
    let min: Value
    let max: Value
    let step: Value.Stride
    @Binding var value: Value
    /// What VoiceOver calls the slider, which otherwise has no name of its own, and what it
    /// reads as the value — "20%" rather than the bare number.
    var accessibility: (label: String, value: String)?

    var body: some View {
        VStack(spacing: 0) {
            slider
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

    @ViewBuilder
    private var slider: some View {
        let slider = Slider(value: $value, in: min ... max, step: step)
        if let accessibility {
            slider
                .accessibilityLabel(accessibility.label)
                .accessibilityValue(accessibility.value)
        } else {
            slider
        }
    }
}
