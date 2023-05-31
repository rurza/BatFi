//
//  Onboarding.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import SwiftUI

struct Onboarding: View {
    @State private var index: Int = 0

    var body: some View {
        PageView(
            numberOfPages: 3,
            index: $index
        ) {
            WelcomeView(action: {
                index = 1
            }).id(0)
            Text("Hello world")
                .id(1)
        }
        .preferredColorScheme(.dark)
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding()
            .frame(width: 420, height: 600)
    }
}
