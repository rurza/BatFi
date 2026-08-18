//
//  InstallHelperView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import Foundation
import L10n
import SwiftUI

struct InstallHelperView: View {
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 20) {
            let l10n = L10n.Onboarding.Label.self
            Group {
                if OnboardingRecordingMode.streamsDesktop {
                    DesktopStreamView()
                } else if OnboardingRecordingMode.showsFill {
                    OnboardingRecordingMode.fillColor
                } else {
                    AVPlayerViewRepresented(player: model.player)
                }
            }
            .edgesIgnoringSafeArea(.all)
            .frame(maxWidth: .infinity)
            .aspectRatio(1.33333, contentMode: .fill)
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.almostDone)
                    .font(.system(size: 24, weight: .bold))
                Text(l10n.helperDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Text(l10n.helperRequiresAdmin)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            // Required, otherwise the text renders centred — a SwiftUI quirk the previous
            // version of this file worked around on its own last row.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.leading, .bottom, .trailing], 20)
        }
    }
}
