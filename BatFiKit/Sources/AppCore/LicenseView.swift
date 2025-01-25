//
//  SwiftUIView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import L10n
import SwiftUI

struct LicenseView: View {
    enum Focus {
        case email
        case license
    }

    @FocusState private var focus: LicenseView.Focus?
    @ObservedObject private var model: LicenseModel

    init(model: LicenseModel) {
        self.model = model
    }

    var body: some View {
        VStack(spacing: 0) {
            unlockView
            Divider()
            purchaseView
                .alert("Unlock failed", isPresented: Binding(get: {
                    model.state.error != nil
                }, set: { _ in
                    model.dimissErrorClicked()
                })) {
                    Button("OK") { }
                } message: {
                    Text(model.state.error?.localizedDescription ?? "Unknown Error")
                }
        }
    }

    @ViewBuilder
    var purchaseView: some View {
        HStack {
            Text("Don't own BatFi yet? Buy it now!")
            Spacer()
            Button {
                model.purchaseLicenseButtonClicked()
            } label: {
                Text("Buy Now")

            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    var unlockView: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage!)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Unlock BatFi")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("The app requires a valid license key to work. \nProvide the email and license key you received when getting the app.")
                        .padding(.bottom, 10)
                    Form {
                        TextField(text: $model.email) {
                            Text("Email")
                        }
                        .focused($focus, equals: LicenseView.Focus.email)
                        .onSubmit {
                            focus = .license
                        }
                        TextField(text: $model.license) {
                            Text("License")
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
                                Text("I lost my license")
                            })
                            Spacer()
                            ZStack {
                                Button(action: {
                                    model.verifyLicenseButtonClicked()
                                }, label: {
                                    Text("Unlock")
                                })
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
                    .frame(width: 340)
                    Text("The app requires Internet connection to validate the license key.")
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
