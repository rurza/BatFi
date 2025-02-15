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
                                Text(L10n.Settings.Label.tipJarTitle)
                            })
                            .buttonStyle(.link)
                        }
                    } else {
                        GroupBackground {
                            VStack {
                                Button(action: {
                                    licenseModel.openLicenseWindow()
                                }) {
                                    Text(L10n.License.activateBatFi)
                                }
                                .buttonStyle(.borderedProminent)
                                .padding()
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func pane(licenseModel: LicenseModel) -> Pane<Self>  {
        Pane(
            identifier: NSToolbarItem.Identifier("License"),
            title: L10n.Settings.Tab.Title.license,
            toolbarIcon: Bundle.module.image(forResource: "license")!
        ) {
            Self(licenseModel: licenseModel)
        }
    }
}

