//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI

public struct BatteryInfoView: View {
    @StateObject private var model = Model()

    public init() { }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                BatteryMainInfo(
                    label: "Battery",
                    info: "\(model.state?.batteryLevel ?? 0)%"
                )
                if let label = model.timeLabel() {
                    BatteryMainInfo(
                        label: label,
                        info: model.timeDescription()
                    )
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                BatteryAdditionalInfo(
                    label: "Power Source",
                    info: model.state?.powerSource ?? "Unknown"
                )
                BatteryAdditionalInfo(
                    label: "Cycle Count",
                    info: "\(model.state?.batteryCycleCount?.description ?? "Unknown")"
                )
                if let temperature = model.temperatureDescription() {
                    BatteryAdditionalInfo(
                        label: "Temperature",
                        info: temperature
                    )
                }
                if let batteryHealth = model.state?.batteryHealth {
                    BatteryAdditionalInfo(
                        label: "Battery Health",
                        info: batteryHealth
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 200)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct BatteryMainInfo: View {
    private let itemsSpace: CGFloat  = 30

    let label: String
    let info: String

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: itemsSpace)
            Text(info)
            .foregroundColor(.primary)
            .fontWeight(.semibold)
            .font(.body)
        }
    }
}

struct BatteryAdditionalInfo: View {
    private let itemsSpace: CGFloat  = 30

    let label: String
    let info: String

    var body: some View {
        HStack {
            Group {
                Text(label)
                Spacer(minLength: itemsSpace)
                Text(info)
            }
            .foregroundColor(.secondary)
            .font(.callout)
        }
    }
}

struct BatteryInfoView_Previews: PreviewProvider {
    static var previews: some View {
        BatteryInfoView()
    }
}
