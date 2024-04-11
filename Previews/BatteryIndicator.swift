//
//  ContentView.swift
//  Previews
//
//  Created by Adam Różyński on 10/04/2024.
//

import BatteryIndicator
import SwiftUI

struct BatteryIndicatorPreview: View {
    @StateObject var model = BatteryIndicatorView.Model(
        chargingMode: .inhibited,
        batteryLevel: 10,
        monochrome: false,
        showPercentage: false
    )
    @State private var percentage: Double = 55

    var body: some View {
        VStack {
            BatteryIndicatorView(model: model)
                .frame(width: 33, height: 13)
                .padding()

            Divider()
            VStack(alignment: .leading) {
                Toggle("Mono", isOn: $model.monochrome)
                Toggle("%", isOn: $model.showPercentage)
                HStack {
                    Button {
                        if percentage > 0 {
                            percentage -= 1
                        }
                    } label: {
                        Text("-")
                    }
                    Slider(value: $percentage, in: 0 ... 100) {
                        Text("Percentage")
                    }
                    Button {
                        if percentage < 100 {
                            percentage += 1
                        }
                    } label: {
                        Text("+")
                    }
                }
                Picker(selection: $model.chargingMode) {
                    Text("Charging").tag(BatteryIndicatorView.Model.ChargingMode.charging)
                    Text("Discharging").tag(BatteryIndicatorView.Model.ChargingMode.discharging)
                    Text("Inhibited").tag(BatteryIndicatorView.Model.ChargingMode.inhibited)
                    Text("Error").tag(BatteryIndicatorView.Model.ChargingMode.error)
                } label: {
                    Text("Choose mode:")
                }
                .pickerStyle(.radioGroup)
            }
        }
        .onChange(of: percentage, perform: { newValue in
            model.batteryLevel = Int(newValue)
        })
        .padding()
        .frame(width: 300)
        .background(.thinMaterial)
        .presentedWindowStyle(.hiddenTitleBar)
    }
}


#Preview {
    BatteryIndicatorPreview()
}
