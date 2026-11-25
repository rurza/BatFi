//
//  SwiftUIView.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import ConfettiSwiftUI
import L10n
import Shared
import SharedUI
import SwiftUI

struct LicenseView: View {
    enum Focus {
        case license
    }

    @FocusState private var focus: LicenseView.Focus?
    @ObservedObject private var model: LicenseModel
    @ObservedObject private var trialModel: TrialModel
    /// The trial was started while this window was open: it confirms the start rather than
    /// asking for a key.
    @State private var trialStartedHere = false
    /// For previews: the screen to show instead of the models' answer.
    private let previewScreen: LicenceScreen?

    init(
        model: LicenseModel,
        trialModel: TrialModel,
        previewScreen: LicenceScreen? = nil,
        previewTrialStartedHere: Bool = false
    ) {
        self.model = model
        self.trialModel = trialModel
        self.previewScreen = previewScreen
        _trialStartedHere = State(initialValue: previewTrialStartedHere)
    }

    private var screen: LicenceScreen {
        previewScreen ?? LicenceScreen(licenseModel: model, trialModel: trialModel, now: .now)
    }

    private var showsTrialStarted: Bool {
        guard trialStartedHere, case .trialRunning = screen else { return false }
        return true
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                unlockView
                if case let .offerTrial(isStarting) = screen {
                    Divider()
                    trialOfferView(isStarting: isStarting)
                }
                Divider()
                purchaseView
            }
            .opacity(model.state.license == nil && !showsTrialStarted ? 1 : 0)
            Text(L10n.License.thankYou)
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()
                .opacity(model.state.license != nil ? 1 : 0)
            trialStartedView
                .opacity(showsTrialStarted && model.state.license == nil ? 1 : 0)
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
        .onChange(of: trialModel.status) { old, new in
            if old == .none, case .running = new {
                trialStartedHere = true
            }
        }
        .onDisappear {
            // A window opened again asks for a key beside the running trial, as one opened
            // later does, rather than confirming the start again.
            trialStartedHere = false
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
            // Once the trial has ended, buying is the way on.
            .prominent(isTrialEnded, tint: .appAccent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    /// The trial on offer, between the key and buying: the start button and what starting
    /// it means, on the same leading edge as the key above it.
    func trialOfferView(isStarting: Bool) -> some View {
        HStack(alignment: .top, spacing: 20) {
            // The icon's column, kept empty so this lines up with the text beside the icon.
            Color.clear
                .frame(width: 64, height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    trialModel.startTrialButtonClicked()
                } label: {
                    Text(L10n.Trial.startTrial(Constant.trialLengthInDays))
                }
                .tint(.appAccent)
                .buttonStyle(.borderedProminent)
                .disabled(isStarting)
                Text(L10n.Trial.startNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 360, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    /// Shown in place of the key once the trial is started from this window, as "Thank You"
    /// is once a key is accepted.
    @ViewBuilder
    var trialStartedView: some View {
        if case let .trialRunning(until, _) = screen {
            VStack(spacing: 6) {
                Text(L10n.Trial.freeTrial)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(L10n.Trial.endsOn(until.formatted(date: .long, time: .omitted)))
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var isTrialEnded: Bool {
        if case .trialEnded = screen { true } else { false }
    }

    private var title: String {
        switch screen {
        case .trialRunning: L10n.Trial.freeTrial
        case .trialEnded: L10n.Trial.ended
        case .licensed, .undetermined, .activateOnly, .offerTrial: L10n.License.activateBatFi
        }
    }

    private var message: String {
        switch screen {
        case let .trialRunning(until, _): L10n.Trial.endsOn(until.formatted(date: .long, time: .omitted))
        case .licensed, .undetermined, .activateOnly, .offerTrial, .trialEnded: L10n.License.requiresLicense
        }
    }

    /// The activate button is the window's one prominent button, except where starting the
    /// trial or buying is the way on.
    private var activateIsProminent: Bool {
        switch screen {
        case .offerTrial, .trialEnded: false
        case .licensed, .undetermined, .activateOnly, .trialRunning: true
        }
    }

    var unlockView: some View {
        HStack(alignment: .top, spacing: 20) {
            let l10n = L10n.License.self
            Image(nsImage: NSApp.applicationIconImage!)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text(message)
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
                                .prominent(activateIsProminent, tint: .appAccent)
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

private extension View {
    /// The bordered prominent style in `tint` when `isProminent`; the default button otherwise.
    @ViewBuilder
    func prominent(_ isProminent: Bool, tint: Color) -> some View {
        if isProminent {
            self.tint(tint).buttonStyle(.borderedProminent)
        } else {
            self
        }
    }
}

// MARK: - Previews

private let previewEnd = Date.now.addingTimeInterval(5 * 86400)

#Preview("Activate") {
    let trialModel = TrialModel()
    LicenseView(model: LicenseModel(trialModel: trialModel), trialModel: trialModel, previewScreen: .activateOnly)
        .frame(width: 550)
}

#Preview("Offer trial") {
    let trialModel = TrialModel()
    LicenseView(model: LicenseModel(trialModel: trialModel), trialModel: trialModel, previewScreen: .offerTrial(isStarting: false))
        .frame(width: 550)
}

#Preview("Offer trial, starting") {
    let trialModel = TrialModel()
    LicenseView(model: LicenseModel(trialModel: trialModel), trialModel: trialModel, previewScreen: .offerTrial(isStarting: true))
        .frame(width: 550)
}

#Preview("Trial running") {
    let trialModel = TrialModel()
    LicenseView(model: LicenseModel(trialModel: trialModel), trialModel: trialModel, previewScreen: .trialRunning(until: previewEnd, daysLeft: 5))
        .frame(width: 550)
}

#Preview("Trial started here") {
    let trialModel = TrialModel()
    LicenseView(
        model: LicenseModel(trialModel: trialModel),
        trialModel: trialModel,
        previewScreen: .trialRunning(until: previewEnd, daysLeft: 5),
        previewTrialStartedHere: true
    )
    .frame(width: 550)
}

#Preview("Trial ended") {
    let trialModel = TrialModel()
    LicenseView(model: LicenseModel(trialModel: trialModel), trialModel: trialModel, previewScreen: .trialEnded(at: .now))
        .frame(width: 550)
}
