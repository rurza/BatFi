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
                            Text("Enjoying BatFi?")
                                .font(.headline)
                            Text("""
                            Show your support with a tip!
                            Your contribution helps me keep improving and makes BatFi even better for you.
                            Thank you for being an awesome part of our community!
                            """)
                            .multilineTextAlignment(.leading)
                            VStack {
                                HStack {
                                    Group {
                                        Button(action: {
                                            openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar")!)
                                        }, label: {
                                            Text("Tip $1")
                                        })
                                        Button(action: {
                                            openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar?price=5")!)
                                        }, label: {
                                            Text("Tip $5")
                                        })
                                        Button(action: {
                                            openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar?price=10")!)
                                        }, label: {
                                            Text("Tip $10")
                                        })
                                    }
                                    .padding()
                                    .buttonStyle(SecondaryButtonStyle())
                                }
                                Text("The button will open Gumroad website with price already set.")
                                    .settingDescription()
                                Text("You can change the amount before proceeding.")
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
