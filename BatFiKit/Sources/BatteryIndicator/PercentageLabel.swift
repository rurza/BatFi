//
//  PercentageLabel.swift
//
//
//  Created by Adam on 23/05/2023.
//

import SwiftUI

struct PercentageLabel: View {
    @ObservedObject var model: BatteryIndicatorView.Model
    let height: Double

    var body: some View {
        HStack(spacing: 1) {
            chargingModeSymbol
            if model.batteryLevel < 100 {
                if model.chargingMode != .error {
                    let fontHeight = fontSize(height: height, fraction: 0.85)
                    RollingNumberLabel(
                        font: .system(size: fontHeight, weight: .medium),
                        initialValue: model.batteryLevel
                    )
                }
            }
        }
    }

    var chargingModeSymbol: some View {
        Group {
            switch model.chargingMode {
            case .charging:
                Image(systemName: "bolt.fill")
                    .font(
                        .system(
                            size: fontSize(height: height, fraction: 0.6),
                            weight: .medium
                        )
                    )
            case .discharging:
                EmptyView()
            case .inhibited:
                Image(systemName: "pause.fill")
                    .font(
                        .system(
                            size: fontSize(height: height, fraction: 0.6),
                            weight: .regular
                        )
                    )
            case .error:
                Image(systemName: "exclamationmark")
                    .font(
                        .system(
                            size: fontSize(height: height, fraction: 0.8),
                            weight: .heavy
                        )
                    )
            }
        }
        .transition(.opacity)
    }
}
