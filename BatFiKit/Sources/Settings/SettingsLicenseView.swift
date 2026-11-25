//
//  SettingsLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import Clients
import L10n
import License
import SettingsKit
import Shared
import SharedUI
import SwiftUI

struct SettingsLicenseView: View {
    @ObservedObject var licenseModel: LicenseModel
    @ObservedObject var trialModel: TrialModel
    /// For previews: the screen to show instead of the models' answer.
    var previewScreen: LicenceScreen?
    @Environment(\.openURL) private var openURL

    private var screen: LicenceScreen {
        previewScreen ?? LicenceScreen(licenseModel: licenseModel, trialModel: trialModel, now: .now)
    }

    var body: some View {
        Container(contentWidth: settingsContentWidth) {
            Section { EmptyView() } content: {
                VStack {
                    if let license = licenseModel.state.license {
                        ReceiptView(license: license)
                            .frame(width: 300)
                        VStack(spacing: 30) {
                            Button(action: {
                                openURL(URL(string: "https://micropixels.gumroad.com/l/tipjar?price=10")!)
                            }, label: {
                                Text(L10n.Settings.Label.tipJarTitle)
                            })
                            .buttonStyle(.link)
                            Button(role: .destructive, action: {
                                licenseModel.removeLicense()
                            }, label: {
                                Text(L10n.Settings.Label.removeLicense)
                            })
                            .buttonStyle(.bordered)
                        }
                    } else {
                        switch screen {
                        case let .offerTrial(isStarting):
                            offerTrial(isStarting: isStarting)
                        case let .trialRunning(until, _):
                            trial(L10n.Trial.runningUntil(until.formatted(date: .long, time: .omitted)))
                        case .trialEnded:
                            trial(L10n.Trial.ended)
                        case .licensed, .undetermined, .activateOnly:
                            GroupBackground {
                                VStack {
                                    Button(action: {
                                        licenseModel.openLicenseWindow()
                                    }) {
                                        Text(L10n.License.activateBatFi)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .padding()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// Today's pane, with the trial offered under the activate button.
    func offerTrial(isStarting: Bool) -> some View {
        GroupBackground {
            // Equal widths, the wider title setting both, so the pair reads as one block.
            VStack(spacing: 10) {
                Button(action: {
                    licenseModel.openLicenseWindow()
                }) {
                    Text(L10n.License.activateBatFi)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: {
                    // Started in the licence window, which shows the start confirmed, the
                    // trial already ended, or why it could not start.
                    licenseModel.openLicenseWindow()
                    trialModel.startTrialButtonClicked()
                }) {
                    Text(L10n.Trial.startTrial(Constant.trialLengthInDays))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isStarting)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding()
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    /// The trial running or ended: what it is, a way to buy, and a way to enter a key.
    func trial(_ title: String) -> some View {
        GroupBackground {
            VStack(spacing: 16) {
                Text(title)
                    .font(.headline)
                // Stacked at equal widths, as the trial on offer is.
                VStack(spacing: 10) {
                    Button(action: {
                        licenseModel.purchaseLicenseButtonClicked()
                    }) {
                        Text(L10n.License.purchaseBatFi)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button(action: {
                        licenseModel.openLicenseWindow()
                    }) {
                        Text(L10n.License.activateBatFi)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .padding()
        }
    }

    static func pane(licenseModel: LicenseModel) -> Pane<Self>  {
        Pane(
            identifier: NSToolbarItem.Identifier("License"),
            title: L10n.Settings.Tab.Title.license,
            toolbarIcon: Bundle.module.image(forResource: "license")!
        ) {
            Self(licenseModel: licenseModel, trialModel: licenseModel.trialModel)
        }
    }
}

// MARK: - Previews

@MainActor
private func previewPane(_ screen: LicenceScreen) -> some View {
    let trialModel = TrialModel()
    return SettingsLicenseView(
        licenseModel: LicenseModel(trialModel: trialModel),
        trialModel: trialModel,
        previewScreen: screen
    )
}

#Preview("Activate") {
    previewPane(.activateOnly)
}

#Preview("Offer trial") {
    previewPane(.offerTrial(isStarting: false))
}

#Preview("Trial running") {
    previewPane(.trialRunning(until: .now.addingTimeInterval(5 * 86400), daysLeft: 5))
}

#Preview("Trial ended") {
    previewPane(.trialEnded(at: .now))
}

