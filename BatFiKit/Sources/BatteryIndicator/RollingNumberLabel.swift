//
//  RollingNumberLabel.swift
//
//
//  Created by Adam on 17/09/2022.
//

import SwiftUI

struct RollingNumberLabel: View {
    let font: Font
    private let initialValue: Int
    @State private var animationRange: [Int] = []
    @State private var currentValue: Int

    init(
        font: Font,
        initialValue: Int
    ) {
        self.font = font
        self.initialValue = initialValue
        currentValue = initialValue
    }

    var body: some View {
        HStack(spacing: -0.5) {
            ForEach(0 ..< animationRange.count, id: \.self) { index in
                Text("0")
                    .font(font)
                    .opacity(0)
                    .overlay(
                        GeometryReader { proxy in
                            let size = proxy.size
                            VStack(spacing: 0) {
                                ForEach(0 ... 9, id: \.self) { digit in
                                    Text("\(digit)")
                                        .font(font)
                                        .foregroundStyle(.primary)
                                        .frame(width: size.width, height: size.height)
                                }
                            }
                            .monospacedDigit()
                            .offset(y: -CGFloat(animationRange[index]) * size.height)
                        }
                        .clipped()
                    )
            }
        }
        .onAppear {
            animationRange = Array(repeating: 0, count: "\(currentValue)".count)
            updateText(animate: false)
        }
        .onChange(of: initialValue) {
            currentValue = $0
            updateStorage()
        }
    }

    func updateTextWithDelay(_ delay: Double) {
        let milliseconds = Int(delay * 1000)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) {
            updateText(animate: true)
        }
    }

    func updateText(animate: Bool) {
        let stringValue = "\(currentValue)"
        for (index, value) in zip(0 ..< stringValue.count, stringValue) {
            let fraction = min(Double(index) * 0.15, 0.5)
            if animate {
                withAnimation(
                    .interactiveSpring(
                        response: 0.3,
                        dampingFraction: 1.1 - fraction,
                        blendDuration: 1.2 - fraction
                    )
                ) {
                    animationRange[index] = Int(String(value)) ?? 0
                }
            } else {
                animationRange[index] = Int(String(value)) ?? 0
            }
        }
    }

    func updateStorage() {
        let newValueCount = "\(currentValue)".count
        let diff = newValueCount - animationRange.count
        let delay = 0.1

        if diff > 0 {
            for _ in 0 ..< diff {
                withAnimation(.easeIn(duration: delay + 0.05)) {
                    animationRange.append(0)
                }
            }
            updateTextWithDelay(delay)
        } else if diff < 0 {
            for _ in 0 ..< -diff {
                withAnimation(.easeIn(duration: delay)) {
                    _ = animationRange.removeLast()
                }
            }
            updateTextWithDelay(delay)
        } else {
            updateTextWithDelay(0)
        }
    }
}
