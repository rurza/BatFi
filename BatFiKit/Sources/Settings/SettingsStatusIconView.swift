//
//  SettingsStatusIconView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11/04/2025.
//

import Defaults
import L10n
import SettingsKit
import SwiftUI

struct SettingsStatusIconView: View {
    @Default(.showPercentageOnBatteryIcon) private var showPercentageOnBatteryIcon
    @Default(.showTimeLeftNextToStatusIcon) private var showTimeLeftNextToStatusIcon
    @Default(.showBatteryPercentageInStatusIcon) private var batteryPercentage
    @Default(.showMenuBarIcon) private var showMenuBarIcon
    @Default(.monochromeStatusIcon) private var monochrom
    @Default(.showStaticMenuBarIcon) private var showStaticMenuBarIcon
    @State private var showingAlert = false
    @State private var statusIconOption: StatusIconOption = .dynamic

    var body: some View {
        let l10n = L10n.Settings.self
        Container(contentWidth: settingsContentWidth) {
            Section(title: l10n.Button.Label.chooseStatusIconStyle, bottomDivider: false) {
                Picker(selection: $statusIconOption) {
                    Text(l10n.Button.Label.statusIconStyleDynamic).tag(StatusIconOption.dynamic)
                    Text(l10n.Button.Label.statusIconStyleStatic).tag(StatusIconOption.static)
                    Text(l10n.Button.Label.statusIconStyleHidden).tag(StatusIconOption.hidden)
                } label: {
                   EmptyView()
                }
                .pickerStyle(.menu)
                .frame(width: 200, alignment: .leading)
                .padding(.bottom, 8)
                Group {
                    Toggle(l10n.Button.Label.monochromeIcon, isOn: $monochrom)
                    Toggle(l10n.Button.Label.batteryPercentage, isOn: $batteryPercentage)
                    Toggle(l10n.Button.Label.batteryPercentageNextToIcon, isOn: $showPercentageOnBatteryIcon)
                        .offset(x: 19)
                        .disabled(!batteryPercentage)
                    Toggle(l10n.Button.Label.statusIconTimeLeft, isOn: $showTimeLeftNextToStatusIcon)
                }
                .disabled(statusIconOption != .dynamic)
            }
        }
        .onAppear {
            if !showMenuBarIcon {
                statusIconOption = .hidden
            } else if showStaticMenuBarIcon {
                statusIconOption = .static
            } else {
                statusIconOption = .dynamic
            }
        }
        .onChange(of: statusIconOption) { newValue in
            switch newValue {
            case .dynamic:
                showMenuBarIcon = true
                showStaticMenuBarIcon = false
            case .static:
                showMenuBarIcon = true
                showStaticMenuBarIcon = true
            case .hidden:
                showMenuBarIcon = false
                showingAlert = true
            }
        }
        .alert(L10n.Notifications.Alert.Title.statusBarIconHidden, isPresented: $showingAlert) {
            Button(L10n.Notifications.Alert.Button.Label.restoreStatusBarIcon, role: .cancel) {
                if showStaticMenuBarIcon {
                    statusIconOption = .static
                } else {
                    statusIconOption = .dynamic
                }
            }
            Button("OK") { }
        } message: {
            Text(L10n.Notifications.Alert.InformativeText.statusBarIconHidden)
        }
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("Status Icon"),
        title: L10n.Settings.Section.statusIcon,
        toolbarIcon: NSImage(resource: .statusIcon)
    ) {
        Self()
    }
}

private enum StatusIconOption {
    case dynamic
    case `static`
    case hidden
}

#Preview {
    SettingsStatusIconView()
}
