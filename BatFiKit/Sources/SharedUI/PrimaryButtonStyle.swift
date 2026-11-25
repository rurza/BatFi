//
//  PrimaryButtonStyle.swift
//
//
//  Created by Adam Różyński on 19/03/2024.
//

import SwiftUI

public struct PrimaryButtonStyle: ButtonStyle {
    let isLoading: Bool
    let isCompact: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    /// - Parameter isCompact: a shorter button, for a place with no room to spare in height,
    ///   such as over a row of a list that must not change size.
    public init(isLoading: Bool, isCompact: Bool = false) {
        self.isLoading = isLoading
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .foregroundColor(.white)
            .frame(minWidth: 80)
            .padding(.horizontal, isCompact ? 10 : 14)
            .padding(.vertical, isCompact ? 3 : 8)
            .background(derivedBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: isCompact ? 6 : 8, style: .continuous))
            .shadow(color: .accentColor.opacity(isEnabled ? 0.15 : 0), radius: isCompact ? 4 : 8, x: 0, y: isCompact ? 2 : 6)
    }

    var derivedBackgroundColor: Color {
        guard !isLoading else { return .clear }
        if isEnabled {
            return .appAccent
        } else {
            return Color(nsColor: .disabledControlTextColor)
        }
    }
}
