//
//  ReceiptView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 01/02/2025.
//

import Clients
import SwiftUI

public struct ReceiptView: View {
    let license: License

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: license.purchaseDate)
    }

    public init(license: License) {
        self.license = license
    }

    public var body: some View {
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
                    Text("Email:")
                        .font(.body)
                        .monospaced()
                        .fontWeight(.semibold)
                        .foregroundStyle(.black.opacity(0.8))
                    Spacer()
                    Text(license.email)
                        .font(.body)
                        .monospaced()
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("Key:")
                        .font(.body)
                        .monospaced()
                        .fontWeight(.semibold)
                        .foregroundStyle(.black.opacity(0.8))
                    Spacer()
                    Text(license.key)
                        .font(.body)
                        .monospaced()
                        .foregroundStyle(.gray)
                }
            }

            SeparatorView()

            Text("I appreciate your support!")
                .font(.footnote)
                .monospaced()
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
            Image(.micropixels)
                .aspectRatio(contentMode: .fit)
                .frame(height: 20)
                .foregroundStyle(.gray)
        }
        .padding()
        .background(
            VStack(spacing: 0) {
                ReceiptTopShape(purchaseDate: license.purchaseDate)
                    .fill(Color.white)
                    .frame(height: 20)
                    .offset(y: 1)
                Color.white
                    .clipShape(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 4, bottomLeading: 0, bottomTrailing: 0, topTrailing: 4), style: .continuous))
                ReceiptBottomShape(purchaseDate: license.purchaseDate)
                    .fill(Color.white)
                    .frame(height: 20)
                    .offset(y: -1)
            }
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 8)
        .padding()
    }
}


struct ReceiptBottomShape: Shape {
    let purchaseDate: Date

    func path(in rect: CGRect) -> Path {
        var path = Path()

        var randomGenerator = RandomNumberGeneratorForDate(seed: purchaseDate)
        /// Both top and bottom shapes have the same seed for randomGenerator so we want to have different
        /// shapes at top and bottom but still deterministic
        _ = randomGenerator.next()
        let scallopRadius: CGFloat = rect.width / CGFloat.random(in: 40...48, using: &randomGenerator)
        let scallopCount = Int(rect.width / scallopRadius)
        let scallopWidth = rect.width / CGFloat(scallopCount)


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

struct ReceiptTopShape: Shape {
    let purchaseDate: Date

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var randomGenerator = RandomNumberGeneratorForDate(seed: purchaseDate)

        // Define scallop geometry.
        let scallopRadius = rect.width / CGFloat.random(in: 40...48, using: &randomGenerator)
        // Determine how many scallops to draw.
        let scallopCount = Int(rect.width / scallopRadius)
        // Calculate the width available for each scallop.
        let scallopWidth = rect.width / CGFloat(scallopCount)

        // Create a reproducible random generator seeded with the purchase date.

        // Start at the top-left corner.
        path.move(to: CGPoint(x: 0, y: 0))

        // Iterate through scallops along the top edge.
        for i in 0..<scallopCount {
            let centerX = CGFloat(i) * scallopWidth + scallopWidth / 2
            // Introduce a slight random vertical offset.
            let randomOffset = CGFloat.random(in: 0...2, using: &randomGenerator)
            // Vary the scallop radius slightly.
            let radius = scallopRadius / (CGFloat.random(in: 1.9...2.1, using: &randomGenerator)) / 1.2

            // For the first scallop, ensure we draw a line from the starting point
            // to the beginning of the arc.
            if i == 0 {
                path.addLine(to: CGPoint(x: centerX - radius, y: 0))
            }

            // Draw an arc that forms the scallop.
            // Since we want a concave notch along the top, the center of the arc
            // is positioned above the top edge (y is negative).
            // Drawing the arc from 180° to 0° with a clockwise sweep produces
            // the lower half of the circle.
            path.addArc(
                center: CGPoint(x: centerX, y: 0 - randomOffset),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: true
            )

            // For the last scallop, connect the arc to the top-right corner.
            if i == scallopCount - 1 {
                path.addLine(to: CGPoint(x: rect.width, y: 0))
            }
        }

        // Complete the shape by drawing the right edge, bottom edge, and left edge.
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
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

