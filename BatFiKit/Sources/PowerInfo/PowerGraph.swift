//
//  PowerGraph.swift
//
//
//  Created by Adam on 14/10/2023.
//

import L10n
import Shared
import SwiftUI

public struct PowerInfoView: View {
    @StateObject private var model = Model()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading) {
            Text(L10n.Menu.PowerInfo.header)
                .bold()
                .multilineTextAlignment(.leading)
                .foregroundColor(.secondary)
                .font(.callout)
                .padding(.bottom, 10)
            if let powerInfo = model.powerInfo {
                PowerGraph(powerInfo: powerInfo)
            } else {
                HStack {
                    ProgressView()
                        .scaleEffect(x: 0.5, y: 0.5)
                    Text(L10n.Menu.PowerInfo.loading)
                }
                .foregroundColor(.secondary)
                .font(.callout)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private enum PowerGraphItemType: String {
    case battery = "battery.100"
    case external = "bolt.fill"
    case system = "laptopcomputer"
}

private struct PowerGraphItem: View {
    let type: PowerGraphItemType
    let power: Float

    init(type: PowerGraphItemType, power: Float) {
        self.type = type
        self.power = power
    }

    var body: some View {
        GroupBox {
            HStack(spacing: 5) {
                Image(systemName: type.rawValue)
                    .frame(width: 20, height: 20)
                Text(powerFormatter.string(from: Measurement(value: Double(power), unit: UnitPower.watts)))
                    .monospacedDigit()
            }
            .frame(width: 80, height: 20)
        }
    }
}

struct PowerGraph: View {
    let powerInfo: PowerInfo

    init(powerInfo: PowerInfo) {
        self.powerInfo = powerInfo
    }

    private func sourceItems() -> [PowerGraphItem] {
        var items = [PowerGraphItem]()
        if powerInfo.batteryPower > 0 {
            items.append(PowerGraphItem(type: .battery, power: powerInfo.batteryPower))
        }
        if powerInfo.externalPower > 0 {
            items.append(PowerGraphItem(type: .external, power: powerInfo.externalPower))
        }
        items.sort { $0.power > $1.power }
        return items
    }

    private func targetItems() -> [PowerGraphItem] {
        var items = [PowerGraphItem]()
        if powerInfo.batteryPower < 0 {
            items.append(PowerGraphItem(type: .battery, power: abs(powerInfo.batteryPower)))
        }
        items.append(PowerGraphItem(type: .system, power: powerInfo.systemPower))
        items.sort { $0.power > $1.power }
        return items
    }

    var body: some View {
        HStack {
            VStack {
                ForEach(sourceItems(), id: \.type) {
                    $0
                }
            }
            Spacer()
            Image(systemName: "arrow.forward")
            Spacer()
            VStack {
                ForEach(targetItems(), id: \.type) {
                    $0
                }
            }
        }
        .foregroundColor(.secondary)
        .font(.callout)
    }
}
