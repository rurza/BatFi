//
//  SecondaryButtonStyle.swift
//
//
//  Created by Adam Różyński on 25/04/2024.
//

import SwiftUI

public struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    public init() { }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundColor(colorScheme == .dark ? .white : .accentColor)
            .frame(minWidth: 80)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .foregroundColor(.accentColor.opacity(0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.accentColor, lineWidth: 1)
                    }
            }
    }

    var derivedBackgroundColor: Color {
        if isEnabled {
            return .accentColor
        } else {
            return Color(nsColor: .disabledControlTextColor)
        }
    }
}
