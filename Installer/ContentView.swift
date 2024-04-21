//
//  ContentView.swift
//  Installer
//
//  Created by Adam Różyński on 30/03/2024.
//

import L10n
import SharedUI
import SwiftUI

struct ContentView: View {
    @ObservedObject var appInstaller: AppInstaller
    @State private var showingLicense = false

    var body: some View {
        VStack {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage!)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(height: 150)
                    .padding()
                    .padding(.bottom, -10)
                Text(L10n.Installer.name)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            GroupBox {
                VStack {
                    progressDescriptionView
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    BarProgressView(value: appInstaller.installationState.progress)
                    Button(
                        action: {
                            showingLicense.toggle()
                        },
                        label: {
                            Text(L10n.Installer.Button.Label.install)
                        }
                    )
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PrimaryButtonStyle(isLoading: false))
                    .disabled(installButtonIsDisabled)

                }
                .padding()
            }
            .padding()
        }
        .sheet(isPresented: $showingLicense) {
            LicenseView(
                didAccept: {
                    showingLicense = false
                    appInstaller.downloadAndInstallApp()
                },
                didDecline: {
                    showingLicense = false
                }
            )
            .frame(width: 500, height: 700)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    var progressDescriptionView: some View {
        switch appInstaller.installationState {
        case .initial:
            Text(L10n.Installer.Status.ready)
        case .downloading:
            Text(L10n.Installer.Status.downloading)
        case let .downloadError(error):
            Label(L10n.Installer.Status.downloadError(error.localizedDescription), systemImage: "exclamationmark.triangle.fill")
        case .unzipping:
            Text(L10n.Installer.Status.unzipping)
        case let .unzippingError(error):
            Label(L10n.Installer.Status.unzippingError(error.localizedDescription), systemImage: "exclamationmark.triangle.fill")
        case .moving:
            Text(L10n.Installer.Status.installing)
        case let .movingError(error):
            Label(L10n.Installer.Status.installationError(error.localizedDescription), systemImage: "exclamationmark.triangle.fill")
        case .done:
            Text(L10n.Installer.Status.done)
        }
    }

    var installButtonIsDisabled: Bool {
        switch appInstaller.installationState {
        case .downloading, .moving, .unzipping:
            return true
        case .done, .initial, .downloadError, .movingError, .unzippingError:
            return false
        }
    }

}

#Preview {
    ContentView(appInstaller: AppInstaller())
        .frame(width: 340)
}

#Preview {
    ContentView(appInstaller: AppInstaller(installationState: .downloadError(NSError(domain: "", code: 0, userInfo: nil))))
        .frame(width: 340)
}

#Preview {
    ContentView(appInstaller: AppInstaller(installationState: .moving))
        .frame(width: 340)
}

#Preview {
    ContentView(appInstaller: AppInstaller(installationState: .downloading(progress: 0.3)))
        .frame(width: 340)
}
