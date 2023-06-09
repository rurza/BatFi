//
//  FinalView.swift
//  
//
//  Created by Adam on 07/06/2023.
//

import Defaults
import DefaultsKeys
import SwiftUI

struct FinalView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Done")
                    .font(.system(size: 24, weight: .bold))
                Text("BatFi will automatically launch when you log in.")
                    .frame(maxWidth: .infinity, alignment: .leading) // required, otherwise it will render in center, SwiftUI bug
                    .padding(.bottom, 20)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .padding(.bottom, 60)
                OnboardingButton(
                    title: "Done",
                    isLoading: false,
                    action: {
                        model.nextAction()
                    }
                )
                .frame(maxWidth: .infinity)
            }
            
        }
    
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        FinalView(model: .init(didInstallHelper: {}))
            .frame(width: 420, height: 600)
            .preferredColorScheme(.dark)
    }
}
