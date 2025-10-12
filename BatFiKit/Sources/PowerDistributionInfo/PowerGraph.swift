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
    @StateObject private var model = PowerInfoViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.Menu.PowerInfo.header)
                .multilineTextAlignment(.leading)
                .foregroundColor(.secondary)
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
                .frame(maxWidth: .infinity)
            }
        }
        .font(.callout)
    }
}

private enum PowerGraphItemType: String {
    case battery = "battery.100"
    case external = "bolt.fill"
    case system = "laptopcomputer"
}

private struct PowerGraphItemModel {
    let type: PowerGraphItemType
    let power: Float

    init(type: PowerGraphItemType, power: Float) {
        self.type = type
        self.power = power
    }
}

private struct PowerGraphItem: View {
    let model: PowerGraphItemModel

    init(model: PowerGraphItemModel) {
        self.model = model
    }

    var body: some View {
        GroupBox {
            HStack(spacing: 5) {
                Image(systemName: model.type.rawValue)
                    .frame(width: 20, height: 20)
                Text(powerFormatter.string(from: Measurement(value: Double(model.power), unit: UnitPower.watts)))
                    .monospacedDigit()
            }
            .frame(width: 80, height: 20)
        }
    }
}

struct PowerGraph: View {
    let powerInfo: PowerDistributionInfo

    init(powerInfo: PowerDistributionInfo) {
        self.powerInfo = powerInfo
    }
    
    private func sourceItems() -> [PowerGraphItemModel] {
        var items = [PowerGraphItemModel]()
        if powerInfo.batteryPower > 0 {
            items.append(PowerGraphItemModel(type: .battery, power: powerInfo.batteryPower))
        }
        if powerInfo.externalPower > 0 {
            items.append(PowerGraphItemModel(type: .external, power: powerInfo.externalPower))
        }
        items.sort { $0.power > $1.power }
        return items
    }
    
    private func targetItems() -> [PowerGraphItemModel] {
        var items = [PowerGraphItemModel]()
        if powerInfo.batteryPower < 0 {
            items.append(PowerGraphItemModel(type: .battery, power: abs(powerInfo.batteryPower)))
        }
        items.append(PowerGraphItemModel(type: .system, power: powerInfo.systemPower))
        items.sort { $0.power > $1.power }
        return items
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(sourceItems(), id: \.type) { model in
                    PowerGraphItem(model: model)
                }
            }
            Image(systemName: "arrow.forward")
                .foregroundColor(.secondary)
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(targetItems(), id: \.type) { model in
                    PowerGraphItem(model: model)
                }
            }
        }
        .foregroundColor(.secondary)
        .font(.callout)
    }
}
