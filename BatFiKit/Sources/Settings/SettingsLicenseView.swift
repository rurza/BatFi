//
//  SettingsLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import Clients
import License
import SettingsKit
import SharedUI
import SwiftUI

struct SettingsLicenseView: View {
    @ObservedObject var licenseModel: LicenseModel

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section { EmptyView() } content: {
                VStack {
                    if let license = licenseModel.state.license {
                        ReceiptView(license: license)
                            .frame(width: 300)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func pane(licenseModel: LicenseModel) -> Pane<Self>  {
        Pane(
            identifier: NSToolbarItem.Identifier("License"),
            title: "License",
            toolbarIcon: NSImage(
                systemSymbolName: "person.text.rectangle.fill",
                accessibilityDescription: ""
            )!
        ) {
            Self(licenseModel: licenseModel)
        }
    }
}

