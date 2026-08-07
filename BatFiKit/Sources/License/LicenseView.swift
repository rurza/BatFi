//
//  SwiftUIView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import ConfettiSwiftUI
import L10n
import SharedUI
import SwiftUI

struct LicenseView: View {
    enum Focus {
        case license
    }

    @FocusState private var focus: LicenseView.Focus?
    @ObservedObject private var model: LicenseModel

    init(model: LicenseModel) {
        self.model = model
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                unlockView
                Divider()
                purchaseView
            }
            .opacity(model.state.license == nil ? 1 : 0)
            Text(L10n.License.thankYou)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
                .opacity(model.state.license != nil ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .alert(L10n.License.unlockFailed, isPresented: Binding(get: {
            model.state.error != nil
        }, set: { _ in
            model.dimissErrorClicked()
        })) {
            Button(L10n.Common.ok) { }
        } message: {
            Text(model.state.error?.localizedDescription ?? L10n.Common.unknownError)
        }
        .confettiCannon(
            counter: Binding(get: { model.state.license != nil ? 1 : 0 }, set: { _ in }),
            confettiSize: 10,
            openingAngle: Angle(degrees: 30),
            closingAngle: Angle(degrees: 150),
            repetitions: 2,
            repetitionInterval: 0.7
        )
    }

    @ViewBuilder
    var purchaseView: some View {
        let l10n = L10n.License.self
        HStack {
            Text(l10n.buyNow)
            Spacer()
            Button {
                model.purchaseLicenseButtonClicked()
            } label: {
                Text(l10n.purchaseBatFi)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    var unlockView: some View {
        HStack(alignment: .top, spacing: 20) {
            let l10n = L10n.License.self
            Image(nsImage: NSApp.applicationIconImage!)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(l10n.activateBatFi)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(l10n.requiresLicense)
                        .padding(.bottom, 10)
                    Form {
                        TextField(text: $model.license) {
                            Text(l10n.licenseKey)
                        }
                        .focused($focus, equals: LicenseView.Focus.license)
                        .onSubmit {
                            model.verifyLicenseButtonClicked()
                        }
                        .padding(.bottom, 5)
                        HStack {
                            Button(action: {
                                model.lostLicenseButtonClicked()
                            }, label: {
                                Text(l10n.lostLicense)
                            })
                            .buttonStyle(.link)
                            Spacer()
                            ZStack {
                                Button(action: {
                                    model.verifyLicenseButtonClicked()
                                }, label: {
                                    Text(l10n.activateBatFi)
                                })
                                .tint(.appAccent)
                                .buttonStyle(.borderedProminent)
                                .disabled(model.state.isLoading || !model.canVerifyLicense)
                                .opacity(model.state.isLoading ? 0 : 1)
                                .accessibilityHidden(model.state.isLoading)
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .opacity(model.state.isLoading ? 1 : 0)
                            }
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                    Text(l10n.requiresInternet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
        .padding(.top, 10)
    }
}

