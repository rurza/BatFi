//
//  MenuLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import L10n
import License
import SwiftUI

struct MenuLicenseView: View {
    var licenseModel: LicenseModel

    var body: some View {
        let l10n = L10n.License.self
        GroupBox {
            VStack {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(l10n.activateLicenseKeyToUse)
                        .foregroundStyle(.secondary)
                }
                Button(action: {
                    licenseModel.openLicenseWindow()
                }) {
                    Text(l10n.unlockTheApp)
                }
                .buttonStyle(.bordered)
                .padding(.top, 10)
            }
            .padding(15)
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    MenuLicenseView(licenseModel: LicenseModel())
}
