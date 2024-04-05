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

    var body: some View {
        VStack(spacing: 0) {
            Slider(value: $value, in: min ... max, step: step)
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
