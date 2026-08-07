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
import Shared
import SwiftUI

enum OnboardingScreen: Int, CaseIterable {
    case welcome
    case license
    case helper
    case charging

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
                InstallHelperView(model: model).id(OnboardingScreen.helper.rawValue)
                ChargingLimitView(model: model).id(OnboardingScreen.charging.rawValue)
            }
            HStack {
                if model.currentScreen == .helper && !model.helperIsInstalled {
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
            counter: Binding(get: { model.helperIsInstalled ? 1 : 0 }, set: { _ in }),
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
        // Height is shared by every pane and set by the tallest, which is the final one:
        // video (300pt at this width) plus a group that has grown a slider, a toggle and a
        // wrapping recommendation line. At 620 that pane overran the window and "The app is
        // ready to use!" was clipped off the bottom edge. The other panes end in a `Spacer`,
        // so the extra room simply spreads there.
        .frame(width: 420, height: 680)
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
                return L10n.License.activateBatFi
            }
        case .helper:
            // Unconditional now: a successful install advances off this pane, so it never
            // has to offer to complete anything.
            return l10n.installHelper
        case .charging:
            return l10n.complete
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
        /// Whether the helper went in. Until this reorder that was also the end of
        /// onboarding, which is why it used to be called `onboardingIsFinished`; the limit
        /// pane now comes after it, so the two are different moments and the old name would
        /// be read as the wrong one.
        @MainActor @Published
        private(set) var helperIsInstalled = false

        /// What this Mac's charge mechanism turned out to be, resolved once the helper can
        /// answer and before the limit pane is shown. Held here rather than fetched by
        /// `ChargingLimitView` so that pane's very first frame already carries the real
        /// floor — there is no correct value to draw before this is known, which is the
        /// whole reason the pane moved.
        @MainActor @Published
        private(set) var backend: ChargeBackend?
        @Dependency(\.helperClient) private var helperManager
        @Dependency(\.launchAtLogin) private var launchAtLogin
        @Dependency(\.defaults) private var defaults
        @Dependency(\.chargingClient) private var chargingClient
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
                // Reachable again after a successful install if the user taps back through
                // the dots; there is nothing left to install, so advance.
                guard !helperIsInstalled else {
                    if let next = currentScreen.next() {
                        changeScreenTo(next)
                    }
                    return
                }
                Task {
                    /// One unregister/register cycle, to claim a daemon record that another
                    /// copy of BatFi is holding.
                    ///
                    /// Onboarding needs its own, rather than leaving this to
                    /// `HelperConnectionManager`: guidance is suppressed while this window is
                    /// up, so the recovery that runs later would be silent, and this screen
                    /// would already have written `onboardingIsDone` on the strength of a
                    /// helper belonging to somebody else.
                    @MainActor
                    func claimHelperFromOtherCopy() async {
                        try? await helperManager.quitHelper()
                        try? await helperManager.removeHelper()
                        try? await Task.sleep(for: .seconds(1))
                        try? await helperManager.installHelper()
                    }

                    // Explicit, because the compiler infers nested-function isolation from
                    // what the body touches and the ownership check above is nonisolated;
                    // without this the actor-isolated state below stops being reachable.
                    @MainActor
                    func observeHelperStatus(error: Error?) async {
                        var counter = 0
                        var hasClaimedHelper = false
                        for await status in helperManager.observeHelperStatus() {
                            // `.enabled` only means a registration record exists. A record
                            // macOS can never spawn reads `.enabled` forever, so onboarding
                            // used to declare success over a helper that answered nothing.
                            if status == .enabled, (try? await helperManager.pingHelper()) == true {
                                // Reachable is still not enough. Every copy of BatFi on the
                                // disk registers the same daemon label, so a second copy
                                // being onboarded gets `.enabled` and a perfectly good ping
                                // from the *first* copy's helper — and would finish setup
                                // believing it had installed one of its own.
                                if case let .foreign(conflict) = await helperManager.helperOwnership() {
                                    guard !hasClaimedHelper else {
                                        // Claimed once and still not ours, which means the
                                        // other copy is open and registering too. Onboarding
                                        // cannot resolve that; saying so beats looping.
                                        self.helperError = NSError(
                                            domain: Constant.appBundleIdentifier,
                                            code: 0,
                                            userInfo: [NSLocalizedDescriptionKey: L10n.Notifications.Alert.InformativeText
                                                .foreignHelperOtherCopyInstalled(conflict.owningAppPath ?? conflict.runningExecutablePath)]
                                        )
                                        counter += 1
                                        continue
                                    }
                                    hasClaimedHelper = true
                                    await claimHelperFromOtherCopy()
                                    counter += 1
                                    continue
                                }
                                self.helperError = nil
                                // The first moment BatFi can ask, and it must be answered
                                // before the pane that renders the floor appears — a slider
                                // that draws at 50% and corrects itself to 80% is the defect
                                // this reorder exists to remove.
                                await resolveBackend()
                                didInstallHelper()
                                defaults.setValue(.onboardingIsDone, value: true)
                                // Set before the screen change so the navigation ceiling in
                                // `changeScreenToOneWithIndex` has already risen by the time
                                // the limit pane is on screen and its dot is live.
                                helperIsInstalled = true
                                if let next = currentScreen.next() {
                                    changeScreenTo(next)
                                }
                                NSSound(named: "Funk")?.play()
                                break
                            } else if let error, counter == 20 {
                                self.helperError = error as NSError
                            } else if status == .notRegistered, counter == 0 {
                                // Once, not on every 1.5s tick. Re-registering in a loop is
                                // the behaviour most plausibly associated with wedging the
                                // registration record this screen is waiting on.
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
            case .charging:
                // Load-bearing. `.charging` is the last screen, so its `next()` is nil and
                // the old `default:` arm would have made the Complete button do nothing at
                // all. `completeOnboarding()` used to be reached only through the `.helper`
                // guard, which no longer runs last.
                completeOnboarding()
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

        /// Asks the freshly installed helper what this Mac's mechanism is. A failed fetch
        /// leaves `backend` nil, which `ChargeLimitRange` reads as unresolved and answers
        /// with the widest range — the same permissive direction this pane has always taken,
        /// and the only honest one when nothing has been claimed.
        @MainActor
        private func resolveBackend() async {
            if let diagnostics = try? await chargingClient.chargingDiagnostics() {
                backend = ChargeBackend(rawValue: diagnostics.backend)
            }
        }

        /// The furthest screen the page dots may jump to. The limit pane is deliberately
        /// unreachable until the helper is in: that install is the only moment BatFi can
        /// learn this Mac's floor, and a limit slider shown before it is the bug this
        /// ordering fixes — reachable by tapping the last dot even though the flow no
        /// longer leads there.
        @MainActor
        private var highestReachableScreen: OnboardingScreen {
            helperIsInstalled ? .charging : .helper
        }

        @MainActor
        func changeScreenToOneWithIndex(_ index: Int) {
            guard let screen = OnboardingScreen(rawValue: index),
                  licenseModel.hasValidLicense,
                  screen.rawValue <= highestReachableScreen.rawValue
            else { return }
            changeScreenTo(screen)
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
