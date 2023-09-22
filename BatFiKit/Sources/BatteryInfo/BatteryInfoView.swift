//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import Defaults
import SwiftUI
import AppShared
import L10n
import Shared

public struct BatteryInfoView: View {
    @Default(.showPowerDiagram)                 private var showPowerDiagram
    @Default(.showHighEnergyImpactProcesses)    private var showHighEnergyImpactProcesses

    @StateObject private var model = Model()

    public init() { }

    public var body: some View {
        Group {
            let l10n = L10n.BatteryInfo.Label.self
            if let powerState = model.state {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        BatteryMainInfo(
                            label: l10n.Main.battery,
                            info: "\(powerState.batteryLevel)%",
                            primaryForegroundColor: true
                        )
                        if let timeDescription = model.time?.description {
                            BatteryMainInfo(
                                label: timeDescription.label,
                                info: timeDescription.description,
                                primaryForegroundColor: model.time?.hasKnownTime == true
                            )
                        }
                    }
                    SeparatorView()
                    VStack(alignment: .leading, spacing: 7) {
                        if let description = model.modeDescription {
                            BatteryAdditionalInfo(label: l10n.Additional.appMode, info: description)
                        }
                        BatteryAdditionalInfo(
                            label: l10n.Additional.powerSource,
                            info: powerState.powerSource
                        )
                        BatteryAdditionalInfo(
                            label: l10n.Additional.cycleCount,
                            info: "\(powerState.batteryCycleCount)"
                        )
                        if let temperature = model.temperatureDescription() {
                            BatteryAdditionalInfo(
                                label: l10n.Additional.temperature,
                                info: temperature
                            )
                        }
                        BatteryAdditionalInfo(
                            label: l10n.Additional.batteryCapacity,
                            info: percentageFormatter.string(from: NSNumber(floatLiteral: powerState.batteryCapacity))!
                        )
                    }
                    .frame(maxWidth: .infinity)
                    if let powerInfo = model.powerInfo, showPowerDiagram {
                        SeparatorView()
                        BatteryPowerInfo(powerInfo: powerInfo)
                    }

                    if let topCoalitionInfo = model.topCoalitionInfo, showHighEnergyImpactProcesses {
                        SeparatorView()
                        BatteryTopCoalitionInfo(topCoalitionInfo: topCoalitionInfo)
                    }
                }
                .onDisappear {
                    model.cancelObserving()
                }
                .onAppear {
                    model.setUpObserving()
                }
            } else {
                Label(
                    l10n.infoMissing,
                    systemImage: "bolt.trianglebadge.exclamationmark.fill"
                )
                .frame(height: 200)
            }
        }
        .frame(width: 220)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

struct BatteryMainInfo: View {
    private let itemsSpace: CGFloat = 20

    let label: String
    let info: String
    let primaryForegroundColor: Bool

    var body: some View {
        HStack {
            Text(label)
            Spacer(minLength: itemsSpace)
            Text(info)
                .foregroundStyle(primaryForegroundColor ? .primary : .secondary)
                .fontWeight(primaryForegroundColor ? .semibold : .regular)
                .font(.body)
        }
    }
}

struct BatteryAdditionalInfo<Label: View>: View {
    private let itemsSpace: CGFloat = 20

    let label: () -> Label
    let info: String

    init(label: @escaping () -> Label, info: String) {
        self.label = label
        self.info = info
    }

    init(label: String, info: String) where Label == Text {
        self.label = { Text(label) }
        self.info = info
    }

    var body: some View {
        HStack {
            Group {
                label()
                Spacer(minLength: itemsSpace)
                Text(info)
                    .multilineTextAlignment(.trailing)
            }
            .foregroundColor(.secondary)
            .font(.callout)
        }
    }
}

enum BatteryPowerInfoItemType: String {
    case battery = "battery.100"
    case external = "bolt.fill"
    case system = "laptopcomputer"
}

struct BatteryPowerInfoItem: View {
    let type: BatteryPowerInfoItemType
    let power: Float

    init(type: BatteryPowerInfoItemType, power: Float) {
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


struct BatteryPowerInfo: View {
    let powerInfo: PowerInfo

    init(powerInfo: PowerInfo) {
        self.powerInfo = powerInfo
    }

    private func sourceItems() -> [BatteryPowerInfoItem] {
        var items = [BatteryPowerInfoItem]()
        if powerInfo.batteryPower > 0 {
            items.append(BatteryPowerInfoItem(type: .battery, power: powerInfo.batteryPower))
        }
        if powerInfo.externalPower > 0 {
            items.append(BatteryPowerInfoItem(type: .external, power: powerInfo.externalPower))
        }
        items.sort { $0.power > $1.power }
        return items
    }

    private func targetItems() -> [BatteryPowerInfoItem] {
        var items = [BatteryPowerInfoItem]()
        if powerInfo.batteryPower < 0 {
            items.append(BatteryPowerInfoItem(type: .battery, power: abs(powerInfo.batteryPower)))
        }
        items.append(BatteryPowerInfoItem(type: .system, power: powerInfo.systemPower))
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

struct BatteryTopCoalitionInfo: View {
    let topCoalitionInfo: TopCoalitionInfo

    init(topCoalitionInfo: TopCoalitionInfo) {
        self.topCoalitionInfo = topCoalitionInfo
    }

    var body: some View {
        VStack(alignment: .leading) {
            if topCoalitionInfo.topCoalitions.count > 0 {
                Text(L10n.BatteryInfo.Label.TopCoalition.some)
                    .bold()
                ForEach(topCoalitionInfo.topCoalitions, id: \.bundleIdentifier) { coalition in
                    BatteryTopCoalitionInfoItem(coalition: coalition)
                }
            } else {
                Text(L10n.BatteryInfo.Label.TopCoalition.none)
            }
        }
        .foregroundColor(.secondary)
        .font(.callout)
    }
}

struct BatteryTopCoalitionInfoItem: View {
    let coalition: Coalition

    init(coalition: Coalition) {
        self.coalition = coalition
    }

    var body: some View {
        HStack {
            Image(nsImage: coalition.icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .frame(width: 24, height: 24)
            Text(coalition.displayName ?? coalition.bundleIdentifier)
            Spacer()
            Text(energyImpactFormatter.string(from: NSNumber(floatLiteral: coalition.energyImpact))!)
        }
    }
}
