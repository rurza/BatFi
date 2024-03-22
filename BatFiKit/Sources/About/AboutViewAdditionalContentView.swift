//
//  AboutViewAdditionalContentView.swift
//
//
//  Created by Adam on 21/06/2023.
//

import AboutKit
import AppShared
import L10n
import SwiftUI

struct AboutViewAdditionalContentView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Button {
                // Bundle.main because the license is stored in the app directly
                guard let licenseURL = Bundle.main.url(forResource: "license", withExtension: "pdf") else { return }
                NSWorkspace.shared.open(licenseURL)
            } label: {
                Text(L10n.About.Button.Label.license)
            }
            .buttonStyle(.link)
            .foregroundColor(.accentColor)
            HStack(spacing: 24) {
                Button {
                    openURL(URL(string: "https://micropixels.software/batfi")!)
                } label: {
                    Text(L10n.About.Button.Label.website)
                }
                .buttonStyle(PrimaryButtonStyle(isLoading: false))
                .frame(width: 120)
                Button {
                    openURL(URL(string: "https://twitter.com/rurza")!)
                } label: {
                    Text(L10n.About.Button.Label.twitter)
                }
                .frame(width: 120)
                .buttonStyle(PrimaryButtonStyle(isLoading: false))
            }
        }
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        AboutViewAdditionalContentView()
    }
}
