//
//  AboutViewAdditionalContentView.swift
//  
//
//  Created by Adam on 21/06/2023.
//

import AboutKit
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
                Text("License")
            }
            .buttonStyle(.link)
            .foregroundColor(.accentColor)
            HStack(spacing: 24) {
                Button {
                    openURL(URL(string: "https://micropixels.software/batfi")!)
                } label: {
                    Text("Website")
                }
                .buttonStyle(PrimaryActionButtonStyle(backgroundColor: .accentColor, fillParent: true))
                .frame(width: 120)
                Button {
                    openURL(URL(string: "https://twitter.com/rurza")!)
                } label: {
                    Text("Twitter")
                }
                .frame(width: 120)
                .buttonStyle(PrimaryActionButtonStyle(backgroundColor: .accentColor, fillParent: true))
            }
        }
    }
}

struct SwiftUIView_Previews: PreviewProvider {
    static var previews: some View {
        AboutViewAdditionalContentView()
    }
}
