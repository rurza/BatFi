//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import AppShared
import Defaults
import DefaultsKeys
import L10n
import Shared
import SwiftUI

@MainActor
public struct BatteryInfoView: View {
    @EnvironmentObject private var model: Model

    @Default(.showBatteryCycleCount) private var showBatteryCycleCount
    @Default(.showBatteryHealth) private var showBatteryHealth
    @Default(.showBatteryTemperature) private var showBatteryTemperature
    @Default(.showPowerSource) private var showPowerSource

    public init() {}

    public var body: some View {
        Group {
            let l10n = L10n.BatteryInfo.Label.self
            let unknown = "–––"
            let powerState = model.state
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    BatteryMainInfo(
                        label: l10n.Main.battery,
                        info: powerState?.batteryLevel != nil ? "\(powerState!.batteryLevel)%" : unknown,
                        primaryForegroundColor: true
                    )
                    .fontWeight(.bold)
                    if let timeDescription = model.time?.description {
                        BatteryAdditionalInfo(
                            label: timeDescription.label,
                            info: timeDescription.description
                        )
                    }
                    if let elapsedTimeDescription = model.elapsedTimeDescription() {
                        BatteryAdditionalInfo(
                            label: l10n.Main.Time.elapsedTime,
                            info: elapsedTimeDescription
                        )
                    }
                    BatteryAdditionalInfo(
                        label: l10n.Additional.appMode,
                        info: model.modeDescription ?? unknown
                    )
                }
                if showPowerSource || showBatteryHealth || showBatteryCycleCount || showBatteryTemperature {
                    SeparatorView()
                }
                VStack(alignment: .leading, spacing: 7) {
                    if showPowerSource {
                        BatteryAdditionalInfo(
                            label: l10n.Additional.powerSource,
                            info: powerState?.powerSource ?? unknown
                        )
                    }
                    if showBatteryCycleCount {
                        BatteryAdditionalInfo(
                            label: l10n.Additional.cycleCount,
                            info: powerState?.batteryCycleCount.description ?? unknown
                        )
                    }
                    if showBatteryTemperature {
                        if let temperature = model.temperatureDescription() {
                            BatteryAdditionalInfo(
                                label: l10n.Additional.temperature,
                                info: temperature
                            )
                        }
                    }
                    if showBatteryHealth {
                        BatteryAdditionalInfo(
                            label: l10n.Additional.batteryCapacity,
                            info: powerState?.batteryHealth ?? l10n.Additional.unknownHealth
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
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
        HStack(alignment: .top) {
            label()
            Spacer(minLength: itemsSpace)
            Text(info)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(.secondary)
        .font(.callout)
    }
}
