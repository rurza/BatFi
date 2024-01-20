//
//  ChargingLimitView.swift
//
//
//  Created by Adam on 01/06/2023.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import SwiftUI

struct ChargingLimitView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 0) {
            let l10n = L10n.Onboarding.Label.self
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.4, contentMode: .fill)
            VStack(alignment: .leading, spacing: 20) {
                Text(l10n.setLimit)
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, -10) // so the space between header and the text is -10
                Text(l10n.setLimitDescription)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    let percent = percentageFormatter.string(from: NSNumber(floatLiteral: Double(chargeLimit) / 100))!
                    Text(L10n.Onboarding.Slider.Label.setLimit(percent))
                    Slider(value: .convert(from: $chargeLimit), in: 60 ... 90, step: 5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("60%")
                    } maximumValueLabel: {
                        Text("90%")
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer()
                Text(l10n.setLimitSetUpLater)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}

struct ChargingLimitView_Previews: PreviewProvider {
    static var previews: some View {
        ChargingLimitView(model: Onboarding.Model(didInstallHelper: {}))
            .frame(width: 420, height: 600)
            .preferredColorScheme(.dark)
    }
}
