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
            if model.batteryLevel < 100 {
                ChargingModeSymbol(model: model, height: height, heightFraction: 0.6)
            }
            let fontHeight = fontSize(height: height, fraction: 0.85)
            RollingNumberLabel(
                font: .system(size: fontHeight, weight: .semibold),
                initialValue: model.batteryLevel
            )
        }
    }
}
