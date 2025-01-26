//
//  MenuLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import SwiftUI

struct MenuLicenseView: View {
    var licenseModel: LicenseModel

    var body: some View {
        GroupBox {
            VStack {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Activate the license key to use the app.")
                        .foregroundStyle(.secondary)
                }
                Button(action: {
                    licenseModel.openLicenseWindow()
                }) {
                    Text("Unlock the app")
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    MenuLicenseView(licenseModel: LicenseModel())
}
