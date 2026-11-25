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
import Shared
import SharedUI
import SwiftUI

struct OnboardingLicenseView: View {
    enum Focus {
        case license
    }

    @ObservedObject var licenseModel: LicenseModel
    @ObservedObject var trialModel: TrialModel
    @ObservedObject var onboardingModel: Onboarding.Model
    /// For previews: the screen to show instead of the models' answer.
    var previewScreen: LicenceScreen?
    @FocusState private var focus: Focus?

    private var screen: LicenceScreen {
        previewScreen ?? LicenceScreen(licenseModel: licenseModel, trialModel: trialModel, now: .now)
    }

    var body: some View {
        VStack(spacing: 0) {
            AVPlayerViewRepresented(player: onboardingModel.player)
                .edgesIgnoringSafeArea(.all)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.4, contentMode: .fill)
                .frame(height: 300)
            Group {
                switch screen {
                case .licensed:
                    licenseActivated
                case .undetermined, .activateOnly, .offerTrial, .trialEnded:
                    activateLicenseView
                case let .trialRunning(until, _):
                    trialStarted(until: until)
                }
            }
            .padding(20)
        }
        .frame(width: 420)
    }

    @ViewBuilder
    var activateLicenseView: some View {
        let l10n = L10n.License.self
        // One leading edge for everything, as the title has always had: the field runs the
        // pane's full width and the lines under it start where it starts.
        VStack(alignment: .leading, spacing: 0) {
            Text(isTrialEnded ? L10n.Trial.ended : l10n.activateLicense)
                .font(.system(size: 24, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            if showsRequiresLicense {
                Text(l10n.requiresLicense)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            Form {
                TextField(text: $licenseModel.license) {
                    Text(l10n.licenseKey)
                }
                .focused($focus, equals: Focus.license)
                .disabled(licenseModel.state.isLoading)
                .onSubmit {
                    licenseModel.verifyLicenseButtonClicked()
                }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            Text(l10n.requiresInternet)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 20) {
                Button(action: {
                    licenseModel.lostLicenseButtonClicked()
                }, label: {
                    Text(l10n.lostLicense)
                })
                .buttonStyle(.link)
                if isTrialEnded {
                    // Buying is the way on once the trial has ended.
                    Button(action: {
                        licenseModel.purchaseLicenseButtonClicked()
                    }, label: {
                        Text(l10n.purchaseBatFi)
                    })
                    .buttonStyle(PrimaryButtonStyle(isLoading: false, isCompact: true))
                } else {
                    Button(action: {
                        licenseModel.purchaseLicenseButtonClicked()
                    }, label: {
                        Text(l10n.purchaseBatFi)
                    })
                    .buttonStyle(.link)
                }
            }
            .padding(.top, 12)
            if case .offerTrial = screen {
                trialOffer
                    .padding(.top, 16)
            }
        }
        .background {
            // Its own view: two alerts on one view do not both present.
            Color.clear
                .alert(L10n.Trial.startFailed, isPresented: Binding(get: {
                    trialModel.startFailure != nil
                }, set: { _ in
                    trialModel.dismissStartFailureClicked()
                })) {
                    Button(L10n.Common.ok) { }
                } message: {
                    Text(trialModel.startFailure?.errorDescription ?? L10n.Common.unknownError)
                }
        }
        .alert(l10n.unlockFailed, isPresented: Binding(get: {
            licenseModel.state.error != nil
        }, set: { _ in
            licenseModel.dimissErrorClicked()
        })) {
            Button(L10n.Common.ok) { }
        } message: {
            Text(licenseModel.state.error?.localizedDescription ?? L10n.Common.unknownError)
        }
        .onAppear {
            focus = .license
        }
    }

    private var isTrialEnded: Bool {
        if case .trialEnded = screen { true } else { false }
    }

    /// Everywhere but the trial on offer. There it does not fit under the video: the pane's
    /// height is fixed by the onboarding window, and in German and French the sentence takes
    /// four lines on top of the trial's note. Once the trial has ended there is room again.
    private var showsRequiresLicense: Bool {
        switch screen {
        case .offerTrial: false
        case .licensed, .undetermined, .activateOnly, .trialRunning, .trialEnded: true
        }
    }

    /// The trial on offer, under the key: what the footer's button starts. The button itself
    /// is the footer's, so the step has one primary action.
    var trialOffer: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text(L10n.Trial.freeTrial)
                .font(.headline)
                .padding(.top, 16)
            Text(L10n.Trial.startNote)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    /// The trial is running: confirmed as an accepted key is, with the day it ends.
    func trialStarted(until: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Trial.freeTrial)
                .font(.system(size: 24, weight: .bold))
            Spacer()
            VStack {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.movingParts.pop(.green))
                Text(L10n.Trial.endsOn(until.formatted(date: .long, time: .omitted)))
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    @ViewBuilder
    var licenseActivated: some View {
        let l10n = L10n.License.self
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.activateLicense)
                .font(.system(size: 24, weight: .bold))
            Spacer()
            VStack {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.movingParts.pop(.green))
                Text(l10n.thankYou)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.top)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Spacer()
        }
    }
}

// MARK: - Previews

private struct OnboardingLicensePreview: View {
    let screen: LicenceScreen

    var body: some View {
        let trialModel = TrialModel()
        let licenseModel = LicenseModel(trialModel: trialModel)
        OnboardingLicenseView(
            licenseModel: licenseModel,
            trialModel: trialModel,
            onboardingModel: Onboarding.Model(
                licenseModel: licenseModel,
                unlockModel: UnlockModel(licenseModel: licenseModel, trialModel: trialModel),
                didInstallHelper: {}
            ),
            previewScreen: screen
        )
        .frame(height: 560)
    }
}

#Preview("Activate") {
    OnboardingLicensePreview(screen: .activateOnly)
}

#Preview("Offer trial") {
    OnboardingLicensePreview(screen: .offerTrial(isStarting: false))
}

#Preview("Offer trial, starting") {
    OnboardingLicensePreview(screen: .offerTrial(isStarting: true))
}

#Preview("Trial running") {
    OnboardingLicensePreview(screen: .trialRunning(until: .now.addingTimeInterval(7 * 86400), daysLeft: 7))
}

#Preview("Trial ended") {
    OnboardingLicensePreview(screen: .trialEnded(at: .now))
}
