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
import Shared
import SharedUI
import SwiftUI

struct MenuContent: View {
    @ObservedObject var licenseModel: LicenseModel
    @ObservedObject var trialModel: TrialModel
    @ObservedObject var unlockModel: UnlockModel
    @Default(.showChart) private var showChart
    @Default(.showPowerDiagram) private var showPowerDiagram
    @Default(.showHighEnergyImpactProcesses) private var showHighEnergyImpactProcesses
    @Default(.automationEnabled) private var automationEnabled
    @Default(.automationRules) private var automationRules
    @Default(.automationActiveRuleID) private var automationActiveRuleID
    @Default(.manageCharging) private var manageCharging

    var body: some View {
        VStack(spacing: 12) {
            if !unlockModel.isUnlocked {
                MenuLicenseView(licenseModel: licenseModel, screen: screen(now: .now))
                    .padding(.top, 4) // for equal visual padding with default horizontal padding
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .trialRunning = screen(now: .now) {
                // In the notice's place, which a running trial never shows. Days left move with
                // the clock while the menu stays open.
                TimelineView(.everyMinute) { context in
                    if case let .trialRunning(_, daysLeft) = screen(now: context.date) {
                        MenuTrialCard(licenseModel: licenseModel, daysLeft: daysLeft)
                    }
                }
                .padding(.top, 4) // for equal visual padding with default horizontal padding
                .fixedSize(horizontal: false, vertical: true)
            }
            BatteryInfoView()
                .fixedSize(horizontal: false, vertical: true)
            SeparatorView()
            // Each section brings its own trailing separator, so a hidden one leaves neither a
            // gap nor a doubled separator. Locked, all of them go — see `MenuSections`.
            let visible = sections
            if visible.chart {
                ChartsView()
                    .frame(height: 120)
                    .clipped()
                SeparatorView()
            }
            if visible.powerDistribution {
                PowerInfoView()
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
            if visible.highEnergyUsage {
                HighEnergyUsageView()
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
            // The same sentence the Charging pane shows, on the same terms: only while a rule
            // is actually holding the limit. A rule that is merely scheduled is not doing
            // anything yet, and the menu has nothing to report about it; nor is one while
            // BatFi is locked, when charging is back with macOS.
            if let activeRule = visible.automationOverride {
                AutomationOverrideCard(rule: activeRule)
                    .fixedSize(horizontal: false, vertical: true)
                SeparatorView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sections: MenuSections {
        MenuSections(
            isUnlocked: unlockModel.isUnlocked,
            showChart: showChart,
            showPowerDiagram: showPowerDiagram,
            showHighEnergyImpactProcesses: showHighEnergyImpactProcesses,
            manageCharging: manageCharging,
            automationEnabled: automationEnabled,
            automationRules: automationRules,
            automationActiveRuleID: automationActiveRuleID
        )
    }

    private func screen(now: Date) -> LicenceScreen {
        LicenceScreen(licenseModel: licenseModel, trialModel: trialModel, now: now)
    }
}
