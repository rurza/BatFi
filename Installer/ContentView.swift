//
//  ContentView.swift
//  Installer
//
//  Created by Adam Różyński on 30/03/2024.
//

import SharedUI
import SwiftUI

struct ContentView: View {
    @ObservedObject var appInstaller: AppInstaller

    var body: some View {
        VStack {
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage!)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(height: 150)
                    .padding()
                    .padding(.bottom, -10)
                Text("Install BatFi")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            GroupBox {
                VStack {
                    progressDescriptionView
                        .foregroundStyle(.secondary)

                    BarProgressView(value: appInstaller.installationState.progress)
                    Button(
                        action: {
                            appInstaller.downloadAndInstallApp()
                        },
                        label: {
                            Text("Install")
                        }
                    )
                    .buttonStyle(PrimaryButtonStyle(isLoading: false))
                    .disabled(installButtonIsDisabled)

                }
                .padding()
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    var progressDescriptionView: some View {
        switch appInstaller.installationState {
        case .initial:
            Text("Ready to install")
        case .downloading:
            Text("Downloading…")
        case let .downloadError(error):
            Label("Download error. \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
        case .unzipping:
            Text("Unzipping…")
        case let .unzippingError(error):
            Label("Unzipping error. \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
        case .moving:
            Text("Installing…")
        case let .movingError(error):
            Label("Installation error. \(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill")
        case .done:
            Text("Done")
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
