//
//  ChargingLimitView.swift
//  
//
//  Created by Adam on 01/06/2023.
//

import Defaults
import DefaultsKeys
import SwiftUI

struct ChargingLimitView: View {
    @Default(.chargeLimit) private var chargeLimit
    @Default(.launchAtLogin) private var launchAtLogin
    @ObservedObject var model: Onboarding.Model

    var body: some View {
        VStack(spacing: 0) {
            AVPlayerViewRepresented(player: model.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.4, contentMode: .fill)
            VStack(alignment: .leading, spacing: 20) {
                Text("Set Charging Limit.")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.bottom, -10) // so the space between header and the text is -10
                Text("Set a maximum charging percentage to prevent overcharging and improve battery longevity.")
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Turn off charging when battery will reach \(Int(chargeLimit), format: .percent)")
                    Slider(value: .convert(from: $chargeLimit), in: 60...90, step: 5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("60%")
                    } maximumValueLabel: {
                        Text("90%")
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer()
                Text("You can modify this setting later in the app's settings.")
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
