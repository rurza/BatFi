//
//  BatteryIndicatorView.swift
//  BatFi
//
//  Created by Adam on 17/05/2023.
//

import SwiftUI

let secondaryOpacity = 0.5

public struct BatteryIndicatorView: View {
    @ObservedObject private var model: Model

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            HStack(spacing: 1) {
                if model.showPercentage {
                    PercentageBatteryIndicatorView(model: model, height: size.height)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    BasicBatteryIndicatorView(model: model, height: size.height)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                HalfCircleShape()
                    .foregroundStyle(.primary)
                    .opacity(secondaryOpacity)
                    .frame(
                        width: size.width / 6,
                        height: size.height / 6
                    )
                    .offset(x: -0.5)
            }
        }
        .animation(.default, value: model.batteryLevel)
        .animation(.default, value: model.chargingMode)
        .animation(.default, value: model.showPercentage)
        .animation(.default, value: model.monochrome)
    }
}

struct HalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addArc(center: CGPoint(x: rect.minX, y: rect.midY), radius: rect.height, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: true)
        return path
    }
}

extension Double {
    var isEven: Bool { remainder(dividingBy: 2) == 0 }
}

func fontSize(height: Double, fraction: Double) -> Double {
    let proportion = round(height * fraction)
    return proportion.isEven ? proportion : proportion + 1
}
