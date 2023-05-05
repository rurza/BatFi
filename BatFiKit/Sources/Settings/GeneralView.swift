//
//  GeneralView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Defaults
import SwiftUI
import SettingsKit
import ServiceManagement

struct GeneralView: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.chargeLimit) private var chargeLimit
    @Default(.manageCharging) private var manageCharging
    @State private var limitInteger: Int = 0

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section(title: "General", bottomDivider: true) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if newValue {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                    }
                Toggle("Hide status bar icon", isOn: $launchAtLogin)
            }
            Section(title: "Battery", bottomDivider: true) {
                Toggle("Automatically manage charging", isOn: $manageCharging)
//                VStack(alignment: .leading, spacing: 0) {
                    Slider(value: $chargeLimit, in: 60...90, step: 5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("60%")
                    } maximumValueLabel: {
                        Text("90%")
                    }
                    .disabled(!manageCharging)
                    Text("Charge up to \(limitInteger, format: .percent)")
                        .foregroundColor(manageCharging ? .primary : .secondary)
//                }
            }
            Section {
                EmptyView()
            } content: {
                Text("80% is the recommended value for a day-to-day usage. You can manually override this settings by using \"Charge to 100%\" command from the menu.")
                    .settingDescription()
            }

        }
        .onAppear {
            self.limitInteger = Int(chargeLimit)
        }
        .onChange(of: chargeLimit) { _ in
            self.limitInteger = Int(chargeLimit)
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("General"),
            title: "General",
            toolbarIcon: NSImage(systemSymbolName: "gear.circle.fill", accessibilityDescription: "General pane")!
        ) {
            Self()
        }

    }()
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
}
