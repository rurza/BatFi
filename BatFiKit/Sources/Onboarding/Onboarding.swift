//
//  Onboarding.swift
//
//
//  Created by Adam on 31/05/2023.
//

import AVKit
import AppCore
import AppShared
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
            model.installAlert?.title ?? alertL10n.Title.helperNotInstalled,
            isPresented: Binding<Bool>(
                get: { model.installAlert != nil },
                set: { _ in model.installAlert = nil }
            ),
            presenting: model.installAlert,
            actions: { _ in
                Button(alertL10n.Button.Label.openSystemSettings, role: .cancel) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            },
            message: { alert in
                Text(alert.message)
            }
        )
        .edgesIgnoringSafeArea(.top)
        // Height is shared by every pane and set by the tallest, which is the final one:
        // video (300pt at this width) plus a group that has grown a slider, a toggle and a
        // wrapping recommendation line. At 620 that pane overran the window and "The app is
        // ready to use!" was clipped off the bottom edge, which is what 680 was sized for.
        //
        // That label has since been removed, and 680 outlived it by 36pt: one line of body
        // text plus the 20pt `VStack` spacing above it. The other panes end in a `Spacer` and
        // simply spread the slack, but the limit pane's `Spacer` sits *above* its settings
        // group to pin the group to the bottom — so slack there opens as a hole in the middle
        // of the pane rather than closing up at the end of it.
        //
        // Load-bearing, not incidental: `PageView` is a `GeometryReader`, which has no
        // intrinsic size and fills whatever it is given, so no pane can size this window.
        .frame(width: 420, height: 644)
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
    /// The three ways this pane can stop short, and the words for each.
    ///
    /// The approval case reuses the sentences the menu already shows for it rather than
    /// writing onboarding its own: it is the same state, the existing text is right, and a
    /// second wording would be a second thing to translate and to keep true.
    enum InstallAlert: Equatable {
        /// Nothing is broken. macOS has the registration and wants a switch turned on.
        case needsApproval
        /// The switch is already on and macOS is refusing the record anyway. The remedy is
        /// the opposite of the one above — off, then on — and telling these apart is the
        /// whole reason this pane stopped trusting `.requiresApproval` on its own.
        case needsManualReset
        /// macOS refused the registration. Carries the reason it gave.
        case installFailed(String)
        /// The reachable helper belongs to another copy of BatFi, and claiming it failed.
        case helperBelongsToAnotherCopy(String)

        var title: String {
            switch self {
            case .needsApproval:
                return L10n.Notifications.Alert.Title.helperNeedsApproval
            case .needsManualReset:
                return L10n.Notifications.Alert.Title.helperNeedsManualReset
            case .installFailed:
                return L10n.Notifications.Alert.Title.helperInstallFailed
            case .helperBelongsToAnotherCopy:
                return L10n.Onboarding.Alert.Title.helperNotInstalled
            }
        }

        var message: String {
            switch self {
            case .needsApproval:
                return L10n.Notifications.Alert.InformativeText.helperNeedsApproval
            case .needsManualReset:
                return L10n.Notifications.Alert.InformativeText.helperNeedsManualReset
            // The reason is worth quoting now that it is only ever an outright refusal:
            // "Operation not permitted" is also what macOS returns while it holds a record
            // pending approval, and that reading is claimed above before it reaches here.
            case let .installFailed(reason):
                return L10n.Notifications.Alert.InformativeText.helperInstallFailed(reason)
            case let .helperBelongsToAnotherCopy(message):
                return message
            }
        }
    }

    final class Model: ObservableObject {
        let didInstallHelper: () -> Void
        @MainActor @Published
        private(set) var currentScreen: OnboardingScreen = .welcome
        /// Which of the things that can stop this pane is true.
        ///
        /// Replaces a lone `NSError`, which could only ever produce one sentence — "Helper
        /// (still) not installed" — and produced it for the state that least deserves it:
        /// a registration macOS has accepted and is holding for the user's consent.
        @MainActor @Published
        var installAlert: InstallAlert?
        @MainActor @Published
        var isLoading: Bool = false
        /// The running status-observation loop, so a second tap replaces it rather than
        /// stacking another one behind it. Load-bearing now that the button stops spinning
        /// while the loop is still going: before this the button was busy for as long as the
        /// loop lived, and could not be tapped twice.
        @MainActor
        private var installTask: Task<Void, Never>?
        /// The verdict the user has already been shown, so a state that is true on every
        /// 1.5s tick is announced when it becomes true rather than every tick forever.
        @MainActor
        private var announcedProgress: OnboardingInstallProgress?
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
                // Replaces any loop already running rather than stacking a second one behind
                // it. Reachable now that the button stops spinning while the loop continues,
                // which is what lets a refused install be retried from here at all.
                installTask?.cancel()
                installTask = Task {
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
                                        self.installAlert = .helperBelongsToAnotherCopy(
                                            L10n.Notifications.Alert.InformativeText
                                                .foreignHelperOtherCopyInstalled(conflict.owningAppPath ?? conflict.runningExecutablePath)
                                        )
                                        counter += 1
                                        continue
                                    }
                                    hasClaimedHelper = true
                                    await claimHelperFromOtherCopy()
                                    counter += 1
                                    continue
                                }
                                self.installAlert = nil
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
                            } else {
                                // Every reading that is not a working helper now gets a
                                // verdict. `.requiresApproval` used to match no arm at all,
                                // so the loop ran on in silence with the button still busy —
                                // for a state macOS will never resolve on its own, because
                                // it is waiting for the user.
                                announce(OnboardingInstallPolicy.progress(
                                    status: status.helperServiceStatus,
                                    registrationError: error?.localizedDescription,
                                    tick: counter
                                ))
                                if status == .notRegistered, counter == 0 {
                                    // Once, not on every 1.5s tick. Re-registering in a loop
                                    // is the behaviour most plausibly associated with wedging
                                    // the registration record this screen is waiting on.
                                    try? await helperManager.installHelper()
                                }
                            }
                            counter += 1
                        }
                    }
                    isLoading = true
                    announcedProgress = nil
                    do {
                        try await helperManager.installHelper()
                        await observeHelperStatus(error: nil)
                    } catch {
                        await observeHelperStatus(error: error)
                    }
                    // Not when cancelled: a second tap has already replaced this loop and
                    // set the flag for its own attempt, and this line would land after it.
                    if !Task.isCancelled {
                        isLoading = false
                    }
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

        /// Reflects a verdict, and only when it changes.
        ///
        /// The status stream repeats every 1.5s and `.needsApproval` stays true until someone
        /// walks to System Settings, so announcing on every tick would put the alert back on
        /// screen a second and a half after each dismissal, forever. `isLoading` is set every
        /// time regardless: it describes the present state rather than a transition.
        @MainActor
        private func announce(_ progress: OnboardingInstallProgress) {
            isLoading = progress.isBusy
            guard progress != announcedProgress else { return }
            announcedProgress = progress
            switch progress {
            case .waiting:
                installAlert = nil
            case .needsApproval:
                installAlert = .needsApproval
            case .needsManualReset:
                installAlert = .needsManualReset
            case let .failed(reason):
                installAlert = .installFailed(reason)
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
