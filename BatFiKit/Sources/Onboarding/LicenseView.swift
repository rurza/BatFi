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
    @StateObject private var model = LicenseModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Don't own BatFi yet? Buy it now!")
                Spacer()
                OnboardingButton(title: "Buy Now", isLoading: false, action: {
                    model.purchaseLicenseButtonClicked()
                })
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            Divider()
            HStack(alignment: .top, spacing: 20) {
                Image("Icon", bundle: Bundle.module)
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
                        }
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        Text("The app requires Internet connection to validate the license key.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 20)
                        HStack {
                            Button(action: {
                                model.lostLicenseButtonClicked()
                            }, label: {
                                Text("I lost my license")
                            })
                            Spacer()
                            Button(action: {
                                model.verifyLicenseButtonClicked()
                            }, label: {
                                Text("Unlock")
                            })
                            .disabled(model.state.isLoading)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    LicenseView()
        .frame(width: 520)
        .preferredColorScheme(.dark)
}
