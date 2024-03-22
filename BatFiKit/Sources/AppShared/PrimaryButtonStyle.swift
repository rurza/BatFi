//
//  PrimaryButtonStyle.swift
//
//
//  Created by Adam Różyński on 19/03/2024.
//

import SwiftUI

public struct PrimaryButtonStyle: ButtonStyle {
    let isLoading: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    public init(isLoading: Bool) {
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundColor(.white)
            .frame(minWidth: 80)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(derivedBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .accentColor.opacity(0.15), radius: 8, x: 0, y: 6)
    }

    var derivedBackgroundColor: Color {
        guard !isLoading else { return .clear }
        if isEnabled {
            return .accentColor
        } else {
            return Color(nsColor: .disabledControlTextColor)
        }
    }
}
