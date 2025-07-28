//
//  MenuContent.swift
//
//
//  Created by Adam Różyński on 23/04/2024.
//

import AppShared
import BatteryInfo
import Combine
import Defaults
import DefaultsKeys
import HighEnergyUsage
import License
import PowerCharts
import PowerDistributionInfo
import SharedUI
import SwiftUI

struct MenuContent: View {
    var sizePassthrough: PassthroughSubject<CGSize, Never>
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
        .overlay(
            GeometryReader { geometryProxy in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
            }
        )
        .onPreferenceChange(
            SizePreferenceKey.self,
            perform: { size in
                sizePassthrough.send(size)
            }
        )
    }
}

private struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
