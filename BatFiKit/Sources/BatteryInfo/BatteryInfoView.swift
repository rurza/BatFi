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
                        .fontWeight(.bold)
                        if let timeDescription = model.time?.description {
                            BatteryAdditionalInfo(
                                label: timeDescription.label,
                                info: timeDescription.description
                            )
                        }
                    }
                    SeparatorView()
                    VStack(alignment: .leading, spacing: 7) {
                        BatteryAdditionalInfo(
                            label: l10n.Additional.appMode,
                            info: model.modeDescription ?? "–––"
                        )
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
                            info: powerState.batteryHealth ?? l10n.Additional.unknownHealth
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Label(
                    l10n.infoMissing,
                    systemImage: "bolt.trianglebadge.exclamationmark.fill"
                )
                .frame(height: 200)
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


