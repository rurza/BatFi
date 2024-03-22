//
//  OnboardingButton.swift
//
//
//  Created by Adam on 01/06/2023.
//

import AppShared
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

extension ButtonStyle where Self == PrimaryButtonStyle {
    static func onboarding(isLoading: Bool) -> PrimaryButtonStyle { PrimaryButtonStyle(isLoading: isLoading) }
}
