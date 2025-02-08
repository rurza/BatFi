//
//  OnboardingLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import AppCore
import L10n
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
        let l10n = L10n.License.self
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.activateLicense)
                .font(.system(size: 24, weight: .bold))
            Text(l10n.requiresLicense)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
            Form {
                TextField(text: $licenseModel.email) {
                    Text(l10n.email)
                }
                .focused($focus, equals: Focus.email)
                .onSubmit {
                    focus = .license
                }
                .disabled(licenseModel.state.isLoading)
                TextField(text: $licenseModel.license) {
                    Text(l10n.licenseKey)
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
                Text(l10n.requiresInternet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                HStack(spacing: 30) {
                    Button(action: {
                        licenseModel.lostLicenseButtonClicked()
                    }, label: {
                        Text(l10n.lostLicense)
                    })
                    .buttonStyle(.link)
                    Button(action: {
                        licenseModel.purchaseLicenseButtonClicked()
                    }, label: {
                        Text(l10n.purchaseBatFi)
                    })
                    .buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
        }
        .alert(l10n.unlockFailed, isPresented: Binding(get: {
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
        let l10n = L10n.License.self
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.thankYou)
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
