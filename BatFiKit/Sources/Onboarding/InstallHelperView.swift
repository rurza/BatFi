//
//  FinalView.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Foundation
import Defaults
import DefaultsKeys
import SwiftUI

struct InstallHelperView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 20) {
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.33333, contentMode: .fill)
            VStack(alignment: .leading, spacing: 10) {
                Text(model.onboardingIsFinished ? "Done" : "Almost done.")
                .font(.system(size: 24, weight: .bold))
                .animation(.default, value: model.onboardingIsFinished)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BatFi will install helper tool, that will work in background and is able to change your computer's charging mode.")
                        Text("Installing the helper tool requires admin permissions and is essential for BatFi's functionality.")
                            .foregroundStyle(.secondary)
                    }
                    .opacity(model.onboardingIsFinished ? 0 : 1)
                    Text("The app is ready to use!")
                        .foregroundStyle(.secondary)
                        .opacity(model.onboardingIsFinished ? 1 : 0)
                }
                Spacer()
                Toggle("Launch BatFi at login", isOn: $launchAtLogin)
                    .padding(.bottom, -5)
                Text("Recommended. You can change it later in app's settings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // required, otherwise it will render in center, SwiftUI bug
            }
            .padding([.leading, .bottom, .trailing], 20)
        }
    }
}
