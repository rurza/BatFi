//
//  OnboardingLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import AppCore
import License
import Pow
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
                .aspectRatio(1.4, contentMode: .fill)
                .frame(height: 300)
            Group {
                if licenseModel.hasValidLicense {
                    licenseActivated
                } else {
                    activateLicenseView
                }
            }
            .padding(20)
        }
        .frame(width: 420)
    }

    @ViewBuilder
    var activateLicenseView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activate the License")
                .font(.system(size: 24, weight: .bold))

            Text("The app requires a valid license key to work. \nProvide the email and license key you received when getting the app.")
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
            Form {
                TextField(text: $licenseModel.email) {
                    Text("Email")
                }
                .focused($focus, equals: Focus.email)
                .onSubmit {
                    focus = .license
                }
                .disabled(licenseModel.state.isLoading)
                TextField(text: $licenseModel.license) {
                    Text("License")
                }
                .focused($focus, equals: Focus.license)
                .disabled(licenseModel.state.isLoading)
                .onSubmit {
                    licenseModel.verifyLicenseButtonClicked()
                }
                .padding(.bottom, 5)
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 340)
            VStack {
                Text("The app requires Internet connection to validate the license key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                HStack(spacing: 30) {
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
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
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

    @ViewBuilder
    var licenseActivated: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thank You!")
                .font(.system(size: 24, weight: .bold))
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(.green)
                .transition(.movingParts.pop(.green))
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}
