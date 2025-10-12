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
                    .fixedSize(horizontal: false, vertical: true)
            }
            BatteryInfoView()
                .fixedSize(horizontal: false, vertical: true)
            SeparatorView()
            if Defaults[.showChart] {
                ChartsView()
                    .frame(height: 120)
                    .clipped()
                SeparatorView()
            }
            if Defaults[.showPowerDiagram] {
                PowerInfoView()
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
            if Defaults[.showHighEnergyImpactProcesses] {
                HighEnergyUsageView()
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
