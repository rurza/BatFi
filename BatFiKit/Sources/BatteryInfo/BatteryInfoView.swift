//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI
import AppShared
import L10n

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
