//
//  BasicBatteryIndicatorView.swift
//
//
//  Created by Adam on 18/05/2023.
//

import SwiftUI

struct BasicBatteryIndicatorView: View {
    @ObservedObject var model: BatteryIndicatorViewModel
    let height: Double

    var body: some View {
        HStack(spacing: 1) {
            if model.chargingMode == .error {
                ChargingModeSymbol(model: model, height: height, heightFraction: 0.9)
            }
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
                        .foregroundStyle(fillColor)
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
                    } else if model.chargingMode == .inhibited, model.monochrome, model.batteryLevel > 45 {
                        ChargingModeSymbol(model: model, height: height, heightFraction: 0.6)
                    }
                }
            }
            .overlay {
                switch model.chargingMode {
                case .charging:
                    ChargingModeSymbol(model: model, height: height, heightFraction: 0.9)
                        .foregroundStyle(symbolColor)
                case .discharging:
                    EmptyView()
                case .inhibited:
                    if !model.monochrome || (model.monochrome && model.batteryLevel <= 45) {
                        ChargingModeSymbol(model: model, height: height, heightFraction: 0.6)
                            .foregroundStyle(symbolColor)
                    }
                case .error:
                    EmptyView()
                }
            }
        }
    }

    var fillColor: Color {
        if !model.monochrome, model.batteryLevel <= 10 {
            return .red
        } else {
            return .primary.opacity(0.9)
        }
    }

    var symbolColor: Color {
        guard !model.monochrome else {
            return Color.primary
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

private struct ChargingModeSymbol: View {
    @ObservedObject var model: BatteryIndicatorViewModel
    let height: Double
    let heightFraction: Double

    var body: some View {
        let size = fontSize(height: height, fraction: heightFraction)
        Group {
            switch model.chargingMode {
            case .charging:
                Image(systemName: "bolt.fill")
            case .discharging:
                EmptyView()
            case .inhibited:
                Image(systemName: "pause.fill")
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
        .font(.system(size: size, weight: .medium))
    }
}
