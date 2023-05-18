//
//  BatteryIndicatorView.swift
//  BatFi
//
//  Created by Adam on 17/05/2023.
//

import SwiftUI

public struct BatteryIndicatorView: View {

    @ObservedObject private var model: Model

    public init(model: Model) {
        self.model = model
    }

    private let secondaryOpacity = 0.5
    
    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            HStack(spacing: 1) {
                if model.showPercentage {
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
                                .foregroundStyle(primaryColor())
                        }
                        .overlay {
                            if !model.monochrome {
                                PercentageLabel(model: model, height: size.height)
                                    .foregroundColor(.white.opacity(0.86))
                            }
                        }
                        .mask {
                            RoundedRectangle(
                                cornerRadius: size.height / 4, style: .continuous
                            )
                        }
                        .reverseMask {
                            if model.monochrome {
                                PercentageLabel(model: model, height: size.height)
                            }
                        }
                    }
                } else {
                    ZStack {
                        RoundedRectangle(
                            cornerRadius: size.height / 4, style: .continuous
                        )
                        .stroke(lineWidth: 1)
                        .padding(1)
                        .foregroundStyle(.primary)
                        .opacity(secondaryOpacity)
                        GeometryReader { innerProxy in
                            let width = (Double(model.batteryLevel) / 100) * (innerProxy.size.width)
                            Rectangle()
                                .frame(width: width)
                                .mask {
                                    RoundedRectangle(
                                        cornerRadius: size.height / 5, style: .continuous
                                    )
                                }
                        }
                        .padding(2)
                    }
                    .overlay {
                        if !model.monochrome || model.batteryLevel < 50 {
                            ChargingModeSymbol(model: model, height: size.height, heightFraction: 0.6)
                                .foregroundStyle(primaryColor())
                        }
                    }
                    .reverseMask {
                        if model.monochrome && model.batteryLevel >= 50 {
                            ChargingModeSymbol(model: model, height: size.height, heightFraction: 0.6)
                        }
                    }
                }
                HalfCircleShape()
                    .foregroundStyle(.primary)
                    .opacity(secondaryOpacity)
                    .frame(
                        width: size.width / 6,
                        height: size.height / 6
                    )
            }
        }
        .animation(.spring(), value: model.batteryLevel)
        .animation(.spring(), value: model.chargingMode)
    }

    func primaryColor() -> Color {
        guard !model.monochrome else { return Color.primary }
        guard model.batteryLevel > 10 else { return Color.red }
        switch model.chargingMode {
        case .charging:
            return .accentColor
        case .inhibited:
            return .orange
        case .discharging:
            return .primary
        }
    }
}

struct HalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(center: CGPoint(x: rect.minX, y: rect.midY), radius: rect.height , startAngle: .degrees(90), endAngle: .degrees(270), clockwise: true)
        return path
    }
}

extension Double {
    var isEven: Bool { self.remainder(dividingBy: 2) == 0 }
}

#if DEBUG
struct DemoView: View {
    @StateObject var model = BatteryIndicatorView.Model(
        chargingMode: .charging,
        batteryLevel: 20,
        monochrome: false,
        showPercentage: false
    )
    @State private var percentage: Double = 20

    var body: some View {
        VStack {
            let _  = Self._printChanges()
            BatteryIndicatorView(model: model)
                .frame(width: 34, height: 14)
                .padding()

            Divider()
            VStack(alignment: .leading) {
                HStack {
                    Button {
                        if percentage > 0 {
                            percentage -= 1
                        }
                    } label: {
                        Text("-")
                    }
                    Slider(value: $percentage, in: 0...100) {
                        Text("Percentage")
                    }
                    Button {
                        if percentage < 100 {
                            percentage += 1
                        }
                    } label: {
                        Text("+")
                    }
                }
                Picker(selection: $model.chargingMode) {
                    Text("Charging").tag(BatteryIndicatorView.Model.ChargingMode.charging)
                    Text("Discharging").tag(BatteryIndicatorView.Model.ChargingMode.discharging)
                    Text("Inhibited").tag(BatteryIndicatorView.Model.ChargingMode.inhibited)
                } label: {
                    Text("Choose mode:")
                }
                .pickerStyle(.radioGroup)
            }
            Toggle("Mono", isOn: $model.monochrome)
            Toggle("%", isOn: $model.showPercentage)

        }
        .onChange(of: percentage, perform: { newValue in
            model.batteryLevel = Int(newValue)
        })
        .padding()
        .frame(width: 300)
        .background(.thinMaterial)
        .presentedWindowStyle(.hiddenTitleBar)
    }
}

struct DemoView_Previews: PreviewProvider {
    static var previews: some View {
        DemoView()
    }
}
#endif

func fontSize(height: Double, fraction: Double) -> Double {
    let proportion = round(height * fraction)
    return proportion.isEven ? proportion : proportion + 1
}

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

struct ChargingModeSymbol: View {
    @ObservedObject var model: BatteryIndicatorView.Model
    let height: Double
    let heightFraction: Double

    var body: some View {
        let height = fontSize(height: height, fraction: heightFraction)
        Group {
            if case .charging = model.chargingMode {
                Image(systemName: "bolt.fill")
                    .transition(.opacity)
            } else if case .inhibited = model.chargingMode {
                Image(systemName: "pause.fill")
                    .transition(.opacity)
            }
        }
        .font(.system(size: height, weight: .medium))
    }
}
