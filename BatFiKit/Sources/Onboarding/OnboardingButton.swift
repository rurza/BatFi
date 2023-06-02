//
//  OnboardingButton.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import SwiftUI

struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.bold)
            .foregroundColor(.white)
            .frame(minWidth: 80)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .accentColor.opacity(0.15), radius: 8, x: 0, y: 6)
    }
}

extension ButtonStyle where Self == OnboardingButtonStyle {
    static var onboarding: OnboardingButtonStyle { OnboardingButtonStyle() }
}
