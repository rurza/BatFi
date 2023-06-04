//
//  BatteryInfoView.swift
//  BatFi
//
//  Created by Adam on 20/04/2023.
//

import SwiftUI
import AppShared

public struct BatteryInfoView: View {
    @StateObject private var model = Model()

    public init() { }

    public var body: some View {
        Group {
            if let powerState = model.state {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        BatteryMainInfo(
                            label: "Battery",
                            info: "\(powerState.batteryLevel)%",
                            primaryForegroundColor: true
                        )
                        if let description = model.time?.description {
                            BatteryMainInfo(
                                label: description.label,
                                info: description.description,
                                primaryForegroundColor: model.time?.hasKnownTime == true
                            )
                        }
                    }
                    if let description = model.modeDescription {
                        Text(description)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SeparatorView()
                    VStack(alignment: .leading, spacing: 7) {
                        BatteryAdditionalInfo(
                            label: "Power Source",
                            info: powerState.powerSource
                        )
                        BatteryAdditionalInfo(
                            label: "Cycle Count",
                            info: "\(powerState.batteryCycleCount)"
                        )
                        if let temperature = model.temperatureDescription() {
                            BatteryAdditionalInfo(
                                label: "Temperature",
                                info: temperature
                            )
                        }
                        BatteryAdditionalInfo(
                            label: "Battery Health",
                            info: powerState.batteryHealth
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
                    "Info is missing",
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
    private let itemsSpace: CGFloat  = 30

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
    private let itemsSpace: CGFloat  = 30

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
            }
            .foregroundColor(.secondary)
            .font(.callout)
        }
    }
}
