//
//  PageControl.swift
//  NepTunes
//
//  Created by Adam Różyński on 18/07/2021.
//

import SwiftUI

struct PageControl: View {
    let count: Int
    @Binding var index: Int
    private let size: CGFloat = 8

    var body: some View {
        ZStack {
            HStack(spacing: size) {
                ForEach(0 ..< count, id: \.self) { i in
                    Rectangle()
                        .foregroundColor(.secondary.opacity(0.4))
                        .onTapGesture {
                            index = i
                        }
                }
            }
            Circle()
                .foregroundColor(.secondary)
                .frame(width: size, height: size)
                .position(x: size / 2 + CGFloat(index) * 2 * size, y: size / 2)
                .animation(.interactiveSpring(), value: index)
        }
        .mask(
            HStack(spacing: size) {
                ForEach(0 ..< count, id: \.self) { _ in
                    Circle()
                        .frame(width: size, height: size)
                }
            }
        )
        .frame(width: width, height: size)
    }

    var width: CGFloat {
        (size * CGFloat(count)) + (size * (CGFloat(count) - 1))
    }
}

struct PageControl_Previews: PreviewProvider {
    static var previews: some View {
        PageControl(count: 4, index: .constant(2))
    }
}
