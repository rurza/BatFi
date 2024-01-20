//
//  InstallHelperView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import Defaults
import DefaultsKeys
import Foundation
import L10n
import SwiftUI

struct InstallHelperView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 20) {
            let l10n = L10n.Onboarding.self
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.33333, contentMode: .fill)
            VStack(alignment: .leading, spacing: 10) {
                Text(model.onboardingIsFinished ? l10n.Label.done : l10n.Label.almostDone)
                    .font(.system(size: 24, weight: .bold))
                    .animation(.default, value: model.onboardingIsFinished)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l10n.Label.helperDescription)
                        Text(l10n.Label.helperRequiresAdmin)
                            .foregroundStyle(.secondary)
                    }
                    .opacity(model.onboardingIsFinished ? 0 : 1)
                    Text(l10n.Label.appIsReady)
                        .foregroundStyle(.secondary)
                        .opacity(model.onboardingIsFinished ? 1 : 0)
                }
                Spacer()
                Toggle(l10n.Button.Label.launchAtLogin, isOn: $launchAtLogin)
                    .padding(.bottom, -5)
                Text(l10n.Label.launchAtLoginRecommendation)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // required, otherwise it will render in center, SwiftUI bug
            }
            .padding([.leading, .bottom, .trailing], 20)
        }
    }
}
