//
//  Onboarding.swift
//  
//
//  Created by Adam on 31/05/2023.
//

import Clients
import Defaults
import DefaultsKeys
import Dependencies
import ServiceManagement
import SwiftUI

enum OnboardingScreen: Int, CaseIterable {
    case welcome
    case charging
    case helper
    case final
    
    func next() -> OnboardingScreen? {
        OnboardingScreen(rawValue: rawValue + 1)
    }
    
    func previous() -> OnboardingScreen? {
        OnboardingScreen(rawValue: rawValue - 1)
    }

}

struct Onboarding: View {
    @StateObject var model: Model

    init(didInstallHelper: @escaping () -> Void) {
        _model = StateObject(wrappedValue: Model(didInstallHelper: didInstallHelper))
    }

    var body: some View {
        VStack {
            PageView(
                numberOfPages: OnboardingScreen.allCases.count,
                index: model.currentScreen.rawValue
            ) {
                WelcomeView().id(0)
                ChargingLimitView().id(1)
                InstallHelperView().id(2)
                FinalView(model: model).id(3)
            }
            if model.currentScreen != .final {
                HStack {
                    OnboardingButton(title: "Previous", isLoading: false, action: { model.previousAction() })
                        .opacity(model.currentScreen != .welcome ? 1 : 0)
                        .animation(.spring(), value: model.currentScreen)
                        .disabled(model.isLoading)

                    Spacer()
                    OnboardingButton(
                        title: nextButtonTitle,
                        isLoading: model.isLoading,
                        action: { model.nextAction() }
                    )
                    .disabled(model.isLoading)
                    .animation(.spring(), value: model.currentScreen)
                }.overlay(alignment: .center) {
                    PageControl(
                        count: OnboardingScreen.allCases.count,
                        index: Binding(
                            get: { model.currentScreen.rawValue },
                            set: { index in
                                if let screen = OnboardingScreen(rawValue: index) {
                                    model.currentScreen = screen
                                }
                            }
                        )
                    )
                }
            }
        }
        .padding(20)
        .alert(
            "Helper (still) not installed",
            isPresented: Binding<Bool>(
                get: { model.helperError != nil },
                set: { @MainActor _ in model.helperError = nil }
            ),
            actions: {
                Button("Open System Settings", role: .cancel) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                }
            },
            message: {
                VStack {
                    Text(
"""
You can always change it in the System Settings.
Keep in mind that the app won't work without the helper tool.
"""
                    )

                }
            }
        )
        .frame(width: 420, height: 600)
    }

    var nextButtonTitle: String {
        switch model.currentScreen {
        case .welcome:
            return "Get started"
        case .helper:
            return "Install Helper"
        default:
            return "Next"
        }
    }
}

extension Onboarding {
    final class Model: ObservableObject {
        let didInstallHelper: () -> Void
        @MainActor @Published var currentScreen: OnboardingScreen = .welcome
        @MainActor @Published var helperError: NSError?
        @MainActor @Published var isLoading: Bool = false
        @Dependency(\.helperManager) private var helperManager
        @Dependency(\.launchAtLogin) private var launchAtLogin
        @Dependency(\.settingsDefaults) private var settingsDefaults

        init(didInstallHelper: @escaping () -> Void) {
            self.didInstallHelper = didInstallHelper
        }

        @MainActor
        func nextAction() {
            switch currentScreen {
            case .helper:
                Task {
                    @MainActor
                    func observeHelperStatus(error: Error?) async {
                        var counter = 0
                        for await status in helperManager.observeHelperStatus() {
                            if status == .enabled {
                                try? await helperManager.removeHelper()
                                try? await Task.sleep(for: .seconds(1))
                                try? await helperManager.installHelper()
                                self.helperError = nil
                                if let next = currentScreen.next() {
                                    currentScreen = next
                                }
                                didInstallHelper()
                                break
                            } else if let error, counter == 30 {
                                self.helperError = error as NSError
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
            case .final:
                launchAtLogin.launchAtLogin(Defaults[.launchAtLogin])
                _ = settingsDefaults.onboardingIsDone(true)
                NSApp.windows.first?.close()
            default:
                if let next = currentScreen.next() {
                    currentScreen = next
                }
            }
        }
        
        @MainActor
        func previousAction() {
            if let previous = currentScreen.previous() {
                currentScreen = previous
            }
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding(didInstallHelper: {})
            .frame(width: 420, height: 600)
    }
}
