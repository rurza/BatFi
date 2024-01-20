//
//  MenuContainerView.swift
//
//
//  Created by Adam on 27/10/2023.
//

import AppShared
import BatteryInfo
import Defaults
import DefaultsKeys
import HighEnergyUsage
import PowerCharts
import PowerInfo
import SwiftUI

struct MenuContainerView: View {
    @Default(.showPowerDiagram) private var showPowerDiagram
    @Default(.showHighEnergyImpactProcesses) private var showHighEnergyImpactProcesses
    @Default(.showChart) private var showChart

    var body: some View {
        VStack(spacing: 12) {
            let showAdvancedStats = showChart || showPowerDiagram || showHighEnergyImpactProcesses
            BatteryInfoView()
            if showAdvancedStats {
                SeparatorView()
            }
            if showChart {
                VStack {
                    ChartsView()
                        .frame(height: 120)
                    if showPowerDiagram || showHighEnergyImpactProcesses {
                        SeparatorView()
                    }
                }
            }
            if showPowerDiagram {
                VStack {
                    PowerInfoView()
                        .padding(.bottom, 8)
                    if showHighEnergyImpactProcesses {
                        SeparatorView()
                    }
                }
            }
            if showHighEnergyImpactProcesses {
                HighEnergyUsageView()
            }
        }
        .frame(width: 220)
    }
}
