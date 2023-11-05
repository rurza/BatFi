//
//  HighEnergyUsageView.swift
//
//
//  Created by Adam on 24/10/2023.
//

import AppShared
import L10n
import SwiftUI

public struct HighEnergyUsageView: View {
    @StateObject private var model = Model()

    public init() { }

    public var body: some View {
        let l10n = L10n.Menu.HighEnergyUsage.self
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.header)
                .bold()
                .foregroundColor(.secondary)
                .font(.callout)
            Group {
                if let info = model.topCoalitionInfo {
                    if info.topCoalitions.count > 0 {
                        ForEach(info.topCoalitions, id: \.bundleIdentifier) { coalition in
                            BatteryTopCoalitionInfoItem(coalition: coalition)
                        }
                    } else {
                        GroupBox {
                            Text(l10n.none)
                                .padding(6)
                        }
                    }
                } else {
                    VStack {
                        ProgressView()
                            .scaleEffect(x: 0.6, y: 0.6)
                        Text(l10n.loading)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .foregroundColor(.secondary)
        .font(.callout)
        .onAppear(perform: model.startObserving)
        .onDisappear(perform: model.cancelObserving)
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
