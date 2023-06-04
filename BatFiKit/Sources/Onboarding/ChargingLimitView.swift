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

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Set Charging Limit.")
                    .font(.system(size: 24, weight: .bold))
                Text("Set a maximum charging percentage to prevent overcharging and improve battery longevity.")
                    .padding(.bottom, 15)
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
                .padding(.bottom, 30)
                Text("You can modify this setting later in the app's settings.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            }
        }
    }
}

struct ChargingLimitView_Previews: PreviewProvider {
    static var previews: some View {
        ChargingLimitView()
            .frame(width: 420, height: 600)
            .preferredColorScheme(.dark)
    }
}
