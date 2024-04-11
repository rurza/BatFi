//
//  PercentageBatteryIndicatorView.swift
//  BatFi
//
//  Created by Adam on 18/05/2023.
//

import SwiftUI

struct PercentageBatteryIndicatorView: View {
    @ObservedObject var model: BatteryIndicatorView.Model
    let height: Double

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { innerProxy in
                Rectangle()
                    .foregroundStyle(.primary)
                    .opacity(secondaryOpacity)
                Rectangle()
                    .frame(
                        width: (Double(model.batteryLevel) / 100) * (innerProxy.size.width)
                    )
                    .transition(.opacity)
                    .id(model.chargingMode)
                    .foregroundStyle(fillColor)
            }
            .overlay {
                if !model.monochrome, model.chargingMode != .discharging {
                    PercentageLabel(model: model, height: height)
                        .foregroundColor(.white.opacity(0.86))
                }
            }
            .mask {
                RoundedRectangle(
                    cornerRadius: height / 4, style: .continuous
                )
            }
            .reverseMask {
                if model.monochrome || model.chargingMode == .discharging {
                    PercentageLabel(model: model, height: height)
                }
            }
        }
    }

    var fillColor: Color {
        guard !model.monochrome else {
            return Color.primary
        }
        guard model.batteryLevel > 10 else {
            return .red
        }
        switch model.chargingMode {
        case .charging, .inhibited:
            return .accentColor
        case .discharging:
            return .primary
        case .error:
            return .red
        }
    }
}
