//
//  BasicBatteryIndicatorView.swift
//
//
//  Created by Adam on 18/05/2023.
//

import Clients
import Dependencies
import SwiftUI

struct BasicBatteryIndicatorView: View {
    @ObservedObject var model: BatteryIndicatorViewModel
    @Dependency(\.powerModeClient) private var powerModeClient
    @State private var lowPowerMode = false

    let height: Double

    var body: some View {
        HStack(spacing: 1) {
            if model.chargingMode == .error {
                ChargingModeSymbol.error(height: height, heightFraction: 0.9)
            }
            ZStack {
                RoundedRectangle(
                    cornerRadius: height / 4, style: .continuous
                )
                .stroke(lineWidth: 1)
                .padding(1)
                .foregroundStyle(.primary)
                .opacity(1.0)
                GeometryReader { innerProxy in
                    // No fill at all before the first reading. `batteryLevel` defaults to
                    // 0, so this drew a zero-width bar — and `fillColor` read it as 10% or
                    // below and made it red. The user saw an empty red battery, i.e.
                    // "critically low", beside the "–" the percentage label already shows.
                    // The empty outline is the honest picture of "no reading yet".
                    let width = model.hasReading
                        ? (Double(model.batteryLevel) / 100) * (innerProxy.size.width)
                        : 0
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
                        ChargingModeSymbol.charging(height: height, heightFraction: 0.9).offset(x: -0.9, y: 0.1)
                        ChargingModeSymbol.charging(height: height, heightFraction: 0.9).offset(x: 0.9, y: -0.1)
                        ChargingModeSymbol.charging(height: height, heightFraction: 0.9).offset(x: -1.2, y: 0.7)
                        ChargingModeSymbol.charging(height: height, heightFraction: 0.9).offset(x: -1.2, y: 0.4)
                        ChargingModeSymbol.charging(height: height, heightFraction: 0.9).offset(x: 1.2, y: -0.7)
                    } else if model.chargingMode == .inhibited {
                        ChargingModeSymbol.inhitbitedMask(height: height, heightFraction: 0.9)
                    }
                }
            }
            .overlay {
                switch model.chargingMode {
                case .charging:
                    ChargingModeSymbol.charging(height: height, heightFraction: 0.9)
                        .foregroundStyle(symbolColor)
                case .discharging:
                    EmptyView()
                case .inhibited:
                    ChargingModeSymbol.inhibited(height: height, heightFraction: 0.8)
                        .foregroundStyle(symbolColor)
                case .error:
                    EmptyView()
                }
            }
            .task {
                for await powerMode in powerModeClient.observePowerMode() {
                    lowPowerMode = powerMode == .low
                }
            }
        }
    }

    var fillColor: Color {
        guard !lowPowerMode else {
            return .yellow
        }
        // `model.hasReading` guards the red for the same reason: a default `batteryLevel`
        // of 0 is not a low battery.
        if !model.monochrome, model.hasReading, model.batteryLevel <= 10 {
            return .red
        } else {
            return .primary.opacity(0.8)
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
    let height: Double
    let heightFraction: Double
    let name: ImageName

    enum ImageName {
        case system(String)
        case bundle(String)
    }

    var body: some View {
        let size = fontSize(height: height, fraction: heightFraction)
        Group {
            switch name {
            case .system(let name):
                Image(systemName: name)
            case .bundle(let name):
                Image(name, bundle: .module)
            }
        }
        .transition(.opacity)
        .font(.system(size: size, weight: .medium))
    }
}

extension ChargingModeSymbol {
    @ViewBuilder
    static func error(height: Double, heightFraction: Double) -> some View {
        ChargingModeSymbol(height: height, heightFraction: heightFraction, name: .system("exclamationmark"))
            .font(
            .system(
                size: fontSize(height: height, fraction: 0.8),
                weight: .heavy
            )
        )
    }

    static func charging(height: Double, heightFraction: Double) -> some View {
        ChargingModeSymbol(height: height, heightFraction: heightFraction, name: .system("bolt.fill"))
    }

    static func inhitbitedMask(height: Double, heightFraction: Double) -> some View {
        ChargingModeSymbol(height: height, heightFraction: heightFraction, name: .bundle("reversemask.powerplug.portrait.fill"))
    }

    static func inhibited(height: Double, heightFraction: Double) -> some View {
        ChargingModeSymbol(height: height, heightFraction: heightFraction, name: .bundle("powerplug.portrait.fill"))
    }
}
