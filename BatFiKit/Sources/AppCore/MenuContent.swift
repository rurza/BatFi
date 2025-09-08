//
//  MenuContent.swift
//
//
//  Created by Adam Różyński on 23/04/2024.
//

import AppShared
import BatteryInfo
import Defaults
import DefaultsKeys
import HighEnergyUsage
import License
import PowerCharts
import PowerDistributionInfo
import SharedUI
import SwiftUI

struct MenuContent: View {
    @ObservedObject var licenseModel: LicenseModel

    var body: some View {
        VStack(spacing: 12) {
            if !licenseModel.hasValidLicense {
                MenuLicenseView(licenseModel: licenseModel)
                    .padding(.top, 4) // for equal visual padding with default horizontal padding
            }
            BatteryInfoView()
            SeparatorView()
            if Defaults[.showChart] {
                ChartsView()
                    .frame(height: 120)
                    .clipped()
                SeparatorView()
            }
            if Defaults[.showPowerDiagram] {
                PowerInfoView()
                SeparatorView()
            }
            if Defaults[.showHighEnergyImpactProcesses] {
                HighEnergyUsageView()
                SeparatorView()
            }
        }
    }
}
