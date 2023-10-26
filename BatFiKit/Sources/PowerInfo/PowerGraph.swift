//
//  PowerGraph.swift
//
//
//  Created by Adam on 14/10/2023.
//

import L10n
import Shared
import SwiftUI

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
            VStack(spacing: 5) {
                Image(systemName: type.rawValue)
                Text(powerFormatter.string(from: Measurement(value: Double(power), unit: UnitPower.watts)))
            }
            .frame(width: 55, height: 40)
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

public struct PowerInfoView: View {
    @StateObject private var model = Model()

    public init() { }

    public var body: some View {
        VStack(alignment: .leading) {
            Text(L10n.Menu.PowerInfo.header)
                .bold()
                .foregroundColor(.secondary)
                .font(.callout)
                .padding(.bottom, 10)
            if let powerInfo = model.powerInfo {
                PowerGraph(powerInfo: powerInfo)
            } else {
                VStack {
                    ProgressView()
                        .scaleEffect(x: 0.6, y: 0.6)
                    Text(L10n.Menu.PowerInfo.loading)
                }
            }
        }
        .onAppear {
            model.startObserving()
        }
        .onDisappear {
            model.cancelObserving()
        }
    }
}
