//
//  BatteryIndicatorView.swift
//  BatFi
//
//  Created by Adam on 17/05/2023.
//

import SwiftUI

struct BatteryIndicatorView: View {
    let percentage: Int

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            HStack(spacing: 1) {
                GeometryReader { innerProxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .foregroundStyle(.secondary)

                        Rectangle()
                            .frame(
                                width: (Double(percentage) / 100) * (innerProxy.size.width)
                            )
                            .foregroundStyle(.primary)

                    }
                    .reverseMask {
                        Text("\(percentage)")
                            .font(.system(size: round(size.height * 0.8), weight: .bold))
                            .kerning(-0.7)
                    }
                    .mask {
                        RoundedRectangle(
                            cornerRadius: size.height / 4, style: .continuous
                        )
                    }
                }

                HalfCircleShape()
                    .foregroundStyle(.secondary)
                    .frame(
                        width: size.width / 7,
                        height: size.height / 6
                    )
            }
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

#if DEBUG
struct DemoView: View {
    @State private var percentage: Double = 0

    var body: some View {
        VStack {
            let _  = Self._printChanges()
            BatteryIndicatorView(percentage: Int(percentage))
                .animation(.spring(), value: percentage)
                .frame(width: 32, height: 16)
                .padding()

            Slider(value: $percentage, in: 0...100)
        }
        .padding()
        .frame(width: 200)
        .background(Color.yellow)
    }
}

struct DemoView_Previews: PreviewProvider {
    static var previews: some View {
        DemoView()
    }
}
#endif


