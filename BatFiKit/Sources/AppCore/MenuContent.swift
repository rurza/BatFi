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
import Settings
import SharedUI
import SwiftUI

struct MenuContent: View {
    @ObservedObject var licenseModel: LicenseModel
    @Default(.showChart) private var showChart
    @Default(.showPowerDiagram) private var showPowerDiagram
    @Default(.showHighEnergyImpactProcesses) private var showHighEnergyImpactProcesses
    @Default(.automationEnabled) private var automationEnabled
    @Default(.automationRules) private var automationRules
    @Default(.automationActiveRuleID) private var automationActiveRuleID
    @Default(.manageCharging) private var manageCharging

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
            if showChart {
                ChartsView()
                    .frame(height: 120)
                    .clipped()
                SeparatorView()
            }
            if showPowerDiagram {
                PowerInfoView()
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
            if showHighEnergyImpactProcesses {
                HighEnergyUsageView()
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
            // The same sentence the Charging pane shows, on the same terms: only while a rule
            // is actually holding the limit. A rule that is merely scheduled is not doing
            // anything yet, and the menu has nothing to report about it.
            if manageCharging, automationEnabled,
               let activeRule = AutomationEngine.activeRule(in: automationRules, activeRuleID: automationActiveRuleID) {
                AutomationOverrideCard(rule: activeRule)
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
