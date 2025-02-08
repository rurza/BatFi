//
//  SettingsLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import Clients
import L10n
import License
import SettingsKit
import SharedUI
import SwiftUI

struct SettingsLicenseView: View {
    @ObservedObject var licenseModel: LicenseModel
    @Environment(\.openURL) private var openURL


    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section { EmptyView() } content: {
                VStack {
                    if let license = licenseModel.state.license {
                        ReceiptView(license: license)
                            .frame(width: 300)
                        HStack {
                            Button(action: {
                                openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar?price=10")!)
                            }, label: {
                                Text(L10n.Settings.Button.Label.tipJarTip(formattedPrice(10)))
                            })
                            .buttonStyle(.link)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func formattedPrice(_ price: Int) -> String {
        let doubleValue = Double(price)
        let formatter = NumberFormatter()
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        formatter.numberStyle = .currencyAccounting
        return formatter.string(from: NSNumber(value: doubleValue))!
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

