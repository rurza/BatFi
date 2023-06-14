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
            Color.black.ignoresSafeArea(.container, edges: .all)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.onboardingIsFinished ? "Done" : "Almost done.")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 10)
                .animation(.default, value: model.onboardingIsFinished)
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BatFi will install helper tool, that will work in background and is able to change your computer's charging model.")
                        Text("Installing the helper tool requires admin permissions and is essential for BatFi's functionality.")
                            .foregroundStyle(.secondary)
                    }
                    .opacity(model.onboardingIsFinished ? 0 : 1)
                    Text("The app is ready to use!")
                        .foregroundStyle(.secondary)
                        .opacity(model.onboardingIsFinished ? 1 : 0)
                }
                .padding(.bottom, 40)
                Toggle("Launch BatFi at login", isOn: $launchAtLogin)
                Text("Recommended. You can change it later in app's settings.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading) // required, otherwise it will render in center, SwiftUI bug
            }
            .padding([.leading, .bottom, .trailing], 20)
        }
    }
}
