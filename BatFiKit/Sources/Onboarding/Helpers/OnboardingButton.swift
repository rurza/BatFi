//
//  OnboardingButton.swift
//
//
//  Created by Adam on 01/06/2023.
//

import SwiftUI

struct OnboardingButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .opacity(isLoading ? 0 : 1)
                .overlay {
                    ProgressView()
                        .scaleEffect(x: 0.6, y: 0.6)
                        .padding(.vertical, -5)
                        .opacity(isLoading ? 1 : 0)
                }
        }
        .buttonStyle(.onboarding(isLoading: isLoading))
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    let isLoading: Bool
    @Environment(\.isEnabled) private var isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
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

extension ButtonStyle where Self == OnboardingButtonStyle {
    static func onboarding(isLoading: Bool) -> OnboardingButtonStyle { OnboardingButtonStyle(isLoading: isLoading) }
}
