//
//  BasicBatteryIndicatorView.swift
//  
//
//  Created by Adam on 18/05/2023.
//

import SwiftUI

struct BasicBatteryIndicatorView: View {
    @ObservedObject var model: BatteryIndicatorView.Model
    let height: Double

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: height / 4, style: .continuous
            )
            .stroke(lineWidth: 1.5)
            .padding(1)
            .foregroundStyle(.primary)
            .opacity(0.35)
            GeometryReader { innerProxy in
                let width = (Double(model.batteryLevel) / 100) * (innerProxy.size.width)
                Rectangle()
                    .frame(width: width)
            }
            .mask {
                RoundedRectangle(
                    cornerRadius: height / 7, style: .continuous
                )
            }
            .padding(3)
        }
        .overlay {
            if !model.monochrome || model.batteryLevel < 55 {
                ChargingModeSymbol(model: model, height: height, heightFraction: 0.9)
                    .foregroundStyle(model.primaryColor())
                    .shadow(color: .black.opacity(model.batteryLevel > 34 ? 0.3 : 0), radius: 1, x: 1)

            }
        }
        .reverseMask {
            if model.monochrome && model.batteryLevel >= 55 {
                ChargingModeSymbol(model: model, height: height, heightFraction: 0.9)
            }
        }
    }
}
