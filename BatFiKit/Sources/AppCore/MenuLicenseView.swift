//
//  MenuLicenseView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 26/01/2025.
//

import L10n
import License
import Shared
import SwiftUI

/// The notice at the top of the menu while BatFi is not unlocked.
struct MenuLicenseView: View {
    var licenseModel: LicenseModel
    let screen: LicenceScreen

    var body: some View {
        let l10n = L10n.License.self
        GroupBox {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(isTrialEnded ? L10n.Trial.ended : l10n.activateLicenseKeyToUse)
                        .foregroundStyle(.secondary)
                }
                // One prominent button and, under it, a standard one: the same size and shape,
                // full width of the notice, so the two read as a pair.
                VStack(spacing: 8) {
                    if isTrialEnded {
                        // Buying is the way on; a key bought elsewhere can still be entered.
                        MenuNoticeButton(title: L10n.Trial.buyBatFi, isProminent: true) {
                            licenseModel.purchaseLicenseButtonClicked()
                        }
                        MenuNoticeButton(title: l10n.activateBatFi, isProminent: false) {
                            licenseModel.openLicenseWindow()
                        }
                    } else {
                        MenuNoticeButton(title: l10n.activateBatFi, isProminent: true) {
                            licenseModel.openLicenseWindow()
                        }
                    }
                    if case let .offerTrial(isStarting) = screen {
                        MenuNoticeButton(title: L10n.Trial.startTrial(Constant.trialLengthInDays), isProminent: false) {
                            // Started in the licence window, which shows the start confirmed, the
                            // trial already ended, or why it could not start; the menu has no room
                            // for any of those.
                            licenseModel.openLicenseWindow()
                            licenseModel.trialModel.startTrialButtonClicked()
                        }
                        .disabled(isStarting)
                    }
                }
                .padding(.top, 12)
            }
            .padding(15)
            .frame(maxWidth: .infinity)
        }
    }

    private var isTrialEnded: Bool {
        if case .trialEnded = screen { true } else { false }
    }
}

/// The card at the top of the menu while the trial runs, in the place of the notice: the days
/// left and a way to buy. Calmer than the notice, with no warning sign, as nothing is wrong yet.
/// The text sits above the button because, at the menu's width, the two do not fit side by
/// side even in English.
struct MenuTrialCard: View {
    var licenseModel: LicenseModel
    let daysLeft: Int

    var body: some View {
        GroupBox {
            VStack(spacing: 0) {
                Text(L10n.Trial.daysLeft(daysLeft))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                MenuNoticeButton(title: L10n.Trial.buyBatFi, isProminent: true) {
                    licenseModel.purchaseLicenseButtonClicked()
                }
                .padding(.top, 12)
            }
            .padding(15)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A button of a card at the top of the menu, as wide as the card. The standard one drops the
/// menu's accent tint, which would otherwise colour it as a second, paler green.
private struct MenuNoticeButton: View {
    let title: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        if isProminent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered).tint(nil)
        }
    }
}

#Preview("Activate") {
    MenuLicenseView(licenseModel: LicenseModel(trialModel: TrialModel()), screen: .activateOnly)
}

#Preview("Offer trial") {
    MenuLicenseView(licenseModel: LicenseModel(trialModel: TrialModel()), screen: .offerTrial(isStarting: false))
}

#Preview("Trial ended") {
    MenuLicenseView(licenseModel: LicenseModel(trialModel: TrialModel()), screen: .trialEnded(at: .now))
}

#Preview("Trial running") {
    MenuTrialCard(licenseModel: LicenseModel(trialModel: TrialModel()), daysLeft: 7)
        .frame(width: 220) // the menu's content width
        .padding()
}

#Preview("Trial running, one day left") {
    MenuTrialCard(licenseModel: LicenseModel(trialModel: TrialModel()), daysLeft: 1)
        .frame(width: 220) // the menu's content width
        .padding()
}
