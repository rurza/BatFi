//
//  ChargingView.swift
//  
//
//  Created by Adam on 05/05/2023.
//

import Defaults
import SettingsKit
import SwiftUI

struct ChargingView: View {
    @Default(.chargeLimit)                  private var chargeLimit
    @Default(.manageCharging)               private var manageCharging
    @Default(.temperatureSwitch)            private var temperatureSwitch
    @Default(.allowDischargingFullBattery)  private var dischargeBatteryWhenFull
    @Default(.disableSleep)                 private var disableSleep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Container(contentWidth: settingsContentWidth) {
                Section(title: "Battery", bottomDivider: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Automatically manage charging", isOn: $manageCharging)
                        VStack(alignment: .leading, spacing: 2) {
                            Slider(value: $chargeLimit, in: 60...90, step: 5) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("60%")
                            } maximumValueLabel: {
                                Text("90%")
                            }
                            .disabled(!manageCharging)
                        Text("Charge up to \(Int(chargeLimit), format: .percent)")
                                .foregroundColor(manageCharging ? .primary : .secondary)
                        }
                    }
                    .padding(.bottom, 12)
                    Toggle(isOn: $temperatureSwitch) {
                        Text("Automatically turn off charging when the battery gets hot")
                            .help("Turns off charging when the battery is 35°C or more.")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: $dischargeBatteryWhenFull) {
                            Text("Discharge battery when charged over limit")
                                .withBetaLabel()
                                .help("When Macbook's lid is opened, the app can discharge battery until it will reach the limit")
                        }
                        Text("Works only with the lid opened.")
                            .settingDescription()
                    }
                    Toggle(isOn: $disableSleep) {
                        Text("Disable sleep when charging and the limit's not reached")
                            .withBetaLabel()
                            .help("The app will delay sleep so the computer charge up to the limit and then it'll inhibit charging and put the Mac to sleep")
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    Text("80% is the recommended value for a day-to-day usage.")
                    Text("You can manually override this setting by using the \"Charge to 100%\" command from the menu.")
                }
                .settingDescription()
            }
            .padding(.vertical, 20)
            .frame(width: settingsContentWidth)
            .padding(.horizontal, 30)
        }
    }

    static let pane: Pane<Self> = {
        Pane(
            identifier: NSToolbarItem.Identifier("Charging"),
            title: "Charging",
            toolbarIcon: NSImage(systemSymbolName: "bolt.batteryblock.fill", accessibilityDescription: "Notifications pane")!
        ) {
            Self()
        }
    }()
}

struct ChargingView_Previews: PreviewProvider {
    static var previews: some View {
        ChargingView()
    }
}
