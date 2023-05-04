//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI

struct BatteryInfoView: View {
    private let itemsSpace: CGFloat  = 30
    @StateObject private var model = Model()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    HStack {
                        Text("Battery")
                        Spacer(minLength: itemsSpace)
                        Text("\(model.state?.batteryLevel ?? 0)%")
                        .foregroundColor(.primary)
                        .fontWeight(.semibold)
                        .font(.body)
                    }
                    if let label = model.timeLabel() {
                        HStack {
                            Text(label)
                            Spacer(minLength: itemsSpace)
                            Text(model.timeDescription())
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .font(.callout)
                .foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    HStack {
                        Text("Power Source")
                        Spacer(minLength: itemsSpace)
                        if let powerSource = model.state?.powerSource {
                            Text(powerSource)
                        } else {
                            Text("Unknown")
                        }
                    }

                    HStack {
                        Text("Cycle Count")
                        Spacer(minLength: itemsSpace)
                        Text("\(model.state?.batteryCycleCount?.description ?? "Unknown")")
                    }
                    if let temperature = model.state?.batteryTemperature {
                        HStack {
                            Text("Temperature")
                            Spacer(minLength: itemsSpace)
                            Text("\(Measurement(value: temperature, unit: UnitTemperature.celsius), format: .measurement(width: .abbreviated, usage: .person))")
                        }
                    }
                }
                .foregroundColor(.secondary)
                .font(.callout)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 200)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}

struct BatteryInfoView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryInfoView()
    }
}
