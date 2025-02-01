//
//  Onboarding.swift
//
//
//  Created by Adam on 31/05/2023.
//

import AVKit
import AppCore
import Clients
import ConfettiSwiftUI
import Defaults
import DefaultsKeys
import Dependencies
import L10n
import License
import ServiceManagement
import SwiftUI

enum OnboardingScreen: Int, CaseIterable {
    case welcome
    case license
    case charging
    case helper

    func next() -> OnboardingScreen? {
        OnboardingScreen(rawValue: rawValue + 1)
    }

    func previous() -> OnboardingScreen? {
        OnboardingScreen(rawValue: rawValue - 1)
    }
}

struct Onboarding: View {
    @StateObject var model: Model
    @State private var confettiCounter = 0
    @ObservedObject var licenseModel: LicenseModel

    init(licenseModel: LicenseModel, didInstallHelper: @escaping () -> Void) {
        self.licenseModel = licenseModel
        _model = StateObject(wrappedValue: Model(
            licenseModel: licenseModel,
            didInstallHelper: didInstallHelper
        ))
    }

    var body: some View {
        let l10n = L10n.Onboarding.self
        let alertL10n = L10n.Onboarding.Alert.self
        VStack {
            PageView(
                numberOfPages: OnboardingScreen.allCases.count,
                index: model.currentScreen.rawValue
            ) {
                WelcomeView().id(OnboardingScreen.welcome.rawValue)
                OnboardingLicenseView(licenseModel: licenseModel, onboardingModel: model).id(OnboardingScreen.license.rawValue)
                ChargingLimitView(model: model).id(OnboardingScreen.charging.rawValue)
                InstallHelperView(model: model).id(OnboardingScreen.helper.rawValue)
            }
            HStack {
                if model.currentScreen == .helper && !model.onboardingIsFinished {
                    OnboardingButton(title: l10n.Button.Label.previous, isLoading: false, action: { model.previousAction() })
                        .animation(.spring(), value: model.currentScreen)
                        .disabled(model.isLoading)
                }
                Spacer()
                OnboardingButton(
                    title: nextButtonTitle,
                    isLoading: model.isLoading || licenseModel.state.isLoading,
                    action: { model.nextAction() }
                )
                .disabled(nextButtonDisabled)
                .animation(.spring(), value: model.currentScreen)
            }.overlay(alignment: .center) {
                PageControl(
                    count: OnboardingScreen.allCases.count,
                    index: Binding(
                        get: { model.currentScreen.rawValue },
                        set: { index in
                            model.changeScreenToOneWithIndex(index)
                        }
                    )
                )
            }
            .padding([.leading, .bottom, .trailing], 20)
        }
        .confettiCannon(
            counter: Binding(get: { model.onboardingIsFinished ? 1 : 0 }, set: { _ in }),
            confettiSize: 10,
            openingAngle: Angle(degrees: 30),
            closingAngle: Angle(degrees: 150),
            repetitions: 2,
            repetitionInterval: 0.7
        )
        .alert(
            alertL10n.Title.helperNotInstalled,
            isPresented: Binding<Bool>(
                get: { model.helperError != nil },
                set: { _ in model.helperError = nil }
            ),
            actions: {
                Button(alertL10n.Button.Label.openSystemSettings, role: .cancel) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            },
            message: {
                Text(alertL10n.Message.helperNotInstalled)
            }
        )
        .edgesIgnoringSafeArea(.top)
        .frame(width: 420, height: 620)
    }

    var nextButtonTitle: String {
        let l10n = L10n.Onboarding.Button.Label.self
        switch model.currentScreen {
        case .welcome:
            return l10n.getStarted
        case .license:
            if licenseModel.hasValidLicense {
                return l10n.next
            } else {
                return "Unlock"
            }
        case .helper:
            if model.onboardingIsFinished {
                return l10n.complete
            } else {
                return l10n.installHelper
            }
        default:
            return l10n.next
        }
    }

    var nextButtonDisabled: Bool {
        model.isLoading || (!licenseModel.canVerifyLicense && model.currentScreen == .license && !licenseModel.hasValidLicense)
    }
}

extension Onboarding {
    final class Model: ObservableObject {
        let didInstallHelper: () -> Void
        @MainActor @Published
        private(set) var currentScreen: OnboardingScreen = .welcome
        @MainActor @Published
        var helperError: NSError?
        @MainActor @Published
        var isLoading: Bool = false
        @MainActor @Published
        var onboardingIsFinished = false
        @Dependency(\.helperClient) private var helperManager
        @Dependency(\.launchAtLogin) private var launchAtLogin
        @Dependency(\.defaults) private var defaults
        var playerModel: OnboardingPlayerViewModel!
        var licenseModel: LicenseModel

        init(licenseModel: LicenseModel, didInstallHelper: @escaping () -> Void) {
            self.licenseModel = licenseModel
            self.didInstallHelper = didInstallHelper
            playerModel = OnboardingPlayerViewModel($currentScreen.eraseToAnyPublisher())
        }

        @MainActor
        func nextAction() {
            switch currentScreen {
            case .helper:
                guard !onboardingIsFinished else {
                    completeOnboarding()
                    return
                }
                Task {
                    @MainActor
                    func observeHelperStatus(error: Error?) async {
                        var counter = 0
                        for await status in helperManager.observeHelperStatus() {
                            if status == .enabled {
                                self.helperError = nil
                                if let next = currentScreen.next() {
                                    changeScreenTo(next)
                                }
                                didInstallHelper()
                                defaults.setValue(.onboardingIsDone, value: true)
                                onboardingIsFinished = true
                                NSSound(named: "Funk")?.play()
                                break
                            } else if let error, counter == 20 {
                                self.helperError = error as NSError
                            } else if status != .requiresApproval {
                                try? await helperManager.removeHelper()
                                try? await Task.sleep(for: .seconds(1))
                                try? await helperManager.installHelper()
                            }
                            counter += 1
                        }
                    }
                    isLoading = true
                    do {
                        try await helperManager.installHelper()
                        await observeHelperStatus(error: nil)
                    } catch {
                        await observeHelperStatus(error: error)
                    }
                    isLoading = false
                }
            case .license:
                Task {
                    await licenseModel.asyncVerifyLicense()
                    if licenseModel.hasValidLicense, let next = currentScreen.next() {
                        changeScreenTo(next)
                    }
                }
            default:
                if let next = currentScreen.next() {
                    changeScreenTo(next)
                }
            }
        }

        @MainActor
        func previousAction() {
            if let previous = currentScreen.previous() {
                changeScreenTo(previous)
            }
        }

        @MainActor
        func changeScreenToOneWithIndex(_ index: Int) {
            if let screen = OnboardingScreen(rawValue: index) {
                changeScreenTo(screen)
            }
        }

        @MainActor
        private func changeScreenTo(_ screen: OnboardingScreen) {
            currentScreen = screen
            licenseModel.licenseViewOnOnboardingVisibilityDidChange(isVisible: screen == .license)
        }

        @MainActor
        func completeOnboarding() {
            launchAtLogin.launchAtLogin(Defaults[.launchAtLogin])
            NSApp.windows.first { $0.isKind(of: OnboardingWindow.self) }?.close()
        }

        var player: AVPlayer {
            playerModel.player
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding(licenseModel: LicenseModel(), didInstallHelper: {})
            .frame(width: 420, height: 600)
    }
}
