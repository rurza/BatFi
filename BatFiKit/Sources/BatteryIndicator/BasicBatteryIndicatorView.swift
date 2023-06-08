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
            .stroke(lineWidth: 1)
            .padding(1)
            .foregroundStyle(.primary)
            .opacity(0.5)
            GeometryReader { innerProxy in
                let width = (Double(model.batteryLevel) / 100) * (innerProxy.size.width)
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: width)
            }
            .mask {
                RoundedRectangle(
                    cornerRadius: height / 6, style: .continuous
                )
            }
            .padding(2.5)
        }
        .reverseMask {
            ZStack {
                if model.chargingMode == .charging {
                    ChargingModeSymbol(model: model, height: height, heightFraction: 0.9).offset(x: -1.5)
                    ChargingModeSymbol(model: model, height: height, heightFraction: 0.9).offset(x: 1.5)
                    ChargingModeSymbol(model: model, height: height, heightFraction: 0.9).offset(x: -2, y: 1)
                    ChargingModeSymbol(model: model, height: height, heightFraction: 0.9).offset(x: 2, y: -1)
                } else if model.chargingMode == .inhibited {
                    Image(systemName: "rectangle.portrait.fill")
                }
            }
        }
        .overlay {
            ChargingModeSymbol(model: model, height: height, heightFraction: 0.9)
                .foregroundStyle(model.primaryColor())
                .shadow(color: .black.opacity(model.monochrome ? 0 : 0.4), radius: 4, x: 0, y: 2)
        }
    }
}
