//
//  OnboardingLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import AppCore
import SwiftUI

struct OnboardingLicenseView: View {
    enum Focus {
        case email
        case license
    }

    @ObservedObject var licenseModel: LicenseModel
    @ObservedObject var onboardingModel: Onboarding.Model
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(spacing: 0) {
            AVPlayerViewRepresented(player: onboardingModel.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.33333, contentMode: .fill)
            VStack(alignment: .leading, spacing: 10) {
                Text("Unlock BatFi")
                    .font(.system(size: 24, weight: .bold))

                Text("The app requires a valid license key to work. \nProvide the email and license key you received when getting the app.")
                    .padding(.bottom, 10)
                Form {
                    TextField(text: $licenseModel.email) {
                        Text("Email")
                    }
                    .focused($focus, equals: Focus.email)
                    .onSubmit {
                        focus = .license
                    }
                    TextField(text: $licenseModel.license) {
                        Text("License")
                    }
                    .focused($focus, equals: Focus.license)
                    .onSubmit {
                        licenseModel.verifyLicenseButtonClicked()
                    }
                    .padding(.bottom, 5)
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                HStack(spacing: 20) {
                    Button(action: {
                        licenseModel.lostLicenseButtonClicked()
                    }, label: {
                        Text("I lost my license")
                    })
                    .buttonStyle(.link)
                    Button(action: {
                        licenseModel.purchaseLicenseButtonClicked()
                    }, label: {
                        Text("Purchase BatFi")
                    })
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity)
                Text("The app requires Internet connection to validate the license key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
            .frame(width: 420)
        }
        .alert("Unlock failed", isPresented: Binding(get: {
            licenseModel.state.error != nil
        }, set: { _ in
            licenseModel.dimissErrorClicked()
        })) {
            Button("OK") { }
        } message: {
            Text(licenseModel.state.error?.localizedDescription ?? "Unknown Error")
        }
    }
}
