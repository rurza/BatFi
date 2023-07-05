//
//  WelcomeView.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import L10n
import SwiftUI

struct WelcomeView: View {

    var body: some View {
        VStack {
            let l10n = L10n.Onboarding.Label.self
            Image("Icon", bundle: Bundle.module)
                .resizable()
                .frame(width: 300, height: 300)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.extendLife)
                    .font(.system(size: 24, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(l10n.appDescription)
                    .padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)

    }
}

struct WelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeView()
            .frame(width: 420, height: 600)
            .preferredColorScheme(.dark)
    }
}
