//
//  SettingsLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import SettingsKit
import SharedUI
import SwiftUI

struct SettingsLicenseView: View {
    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section { EmptyView() } content: {
                VStack {
                    ThankYouWidget(purchaseDate: Date(timeIntervalSince1970: 1737929764))
                        .frame(width: 300)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("License"),
        title: "License",
        toolbarIcon: NSImage(
            systemSymbolName: "person.text.rectangle.fill",
            accessibilityDescription: ""
        )!
    ) {
        Self()
    }
}

struct ReceiptBottomShape: Shape {
    let purchaseDate: Date

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let scallopRadius: CGFloat = rect.width / 40
        let scallopCount = Int(rect.width / scallopRadius)
        let scallopWidth = rect.width / CGFloat(scallopCount)

        var randomGenerator = RandomNumberGeneratorForDate(seed: purchaseDate)

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height))

        for i in 0..<scallopCount {
            let centerX = CGFloat(i) * scallopWidth + scallopWidth / 2
            let randomOffset = CGFloat.random(in: 0...2, using: &randomGenerator)
            let radius: CGFloat = scallopRadius / (CGFloat.random(in: 1.9...2.1, using: &randomGenerator)) / 1.2
            if i == 0 {
                path.addLine(to: CGPoint(x: centerX - radius, y: rect.height))
            }
            path.addArc(
                center: CGPoint(x: centerX, y: rect.height + randomOffset),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            if i == scallopCount - 1 {
                path.move(to: CGPoint(x: centerX + radius, y: rect.height + randomOffset))
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            }
        }

        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()

        return path
    }
}

struct RandomNumberGeneratorForDate: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Date) {
        let timeInterval = seed.timeIntervalSince1970
        self.state = UInt64(timeInterval.bitPattern)
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1
        return state
    }
}

struct ThankYouWidget: View {
    var purchaseDate: Date

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: purchaseDate)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Thank You")
                .font(.title2)
                .fontWeight(.semibold)
                .monospaced()
                .foregroundStyle(.black.opacity(0.8))

            SeparatorView()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Date:")
                        .monospaced()
                        .fontWeight(.semibold)
                        .foregroundStyle(.black.opacity(0.8))
                    Spacer()
                    Text(formattedDate)
                        .font(.body)
                        .monospaced()
                        .foregroundStyle(.gray)
                }

                HStack {
                    Text("Transaction ID:")
                        .font(.body)
                        .monospaced()
                        .fontWeight(.semibold)
                        .foregroundStyle(.black.opacity(0.8))
                    Spacer()
                    Text("#12345ABC")
                        .font(.body)
                        .monospaced()
                        .foregroundStyle(.gray)
                }
            }

            SeparatorView()

            Text("We appreciate your support!")
                .font(.footnote)
                .monospaced()
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
        }
        .padding()
        .background(
            VStack(spacing: 0) {
                Color.white
                    .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 0, bottomTrailing: 0, topTrailing: 4), style: .continuous))
                ReceiptBottomShape(purchaseDate: purchaseDate)
                    .fill(Color.white)
                    .frame(height: 20)
                    .offset(y: -4)
            }
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 8)
        .padding()
    }
}

#Preview {
    SettingsLicenseView()
}
