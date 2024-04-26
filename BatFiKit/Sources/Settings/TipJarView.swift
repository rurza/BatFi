//
//  TipJarView.swift
//
//
//  Created by Adam Różyński on 25/04/2024.
//

import AppShared
import L10n
import SettingsKit
import SharedUI
import SwiftUI

struct TipJarView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section {
                EmptyView()
            } content: {
                HStack {
                    GroupBackground {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L10n.Settings.Label.tipJarTitle)
                                .font(.headline)
                            Text(L10n.Settings.Label.tipJarBody)
                            .multilineTextAlignment(.leading)
                            VStack {
                                HStack {
                                    Group {
                                        Button(action: {
                                            openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar")!)
                                        }, label: {
                                            Text(L10n.Settings.Button.Label.tipJarTip(formattedPrice(1)))
                                        })
                                        Button(action: {
                                            openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar?price=5")!)
                                        }, label: {
                                            Text(L10n.Settings.Button.Label.tipJarTip(formattedPrice(5)))
                                        })
                                        Button(action: {
                                            openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar?price=10")!)
                                        }, label: {
                                            Text(L10n.Settings.Button.Label.tipJarTip(formattedPrice(10)))
                                        })
                                    }
                                    .padding()
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                                Text(L10n.Settings.Label.tipJarButtonDescription1)
                                    .settingDescription()
                                Text(L10n.Settings.Label.tipJarButtonDescription2)
                                    .settingDescription()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    func formattedPrice(_ price: Int) -> String {
        let doubleValue = Double(price)
        let formatter = NumberFormatter()
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        formatter.numberStyle = .currencyAccounting
        return formatter.string(from: NSNumber(value: doubleValue))!
    }

    static let pane: Pane<Self> = Pane(
        identifier: NSToolbarItem.Identifier("Tip Jar"),
        title: L10n.Settings.Tab.Title.tipJar,
        toolbarIcon: NSImage(
            systemSymbolName: "dollarsign.square",
            accessibilityDescription: ""
        )!
    ) {
        Self()
    }
}

#Preview {
    TipJarView()
}
