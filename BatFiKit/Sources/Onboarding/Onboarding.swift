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

struct Onboarding: View {
    @StateObject var model: Model

    init(didInstallHelper: @escaping () -> Void) {
        _model = StateObject(wrappedValue: Model(didInstallHelper: didInstallHelper))
    }

    var body: some View {
        VStack {
            PageView(
                numberOfPages: model.numberOfPages,
                index: $model.index
            ) {
                WelcomeView().id(0)
                ChargingLimitView().id(1)
                LaunchAtLogin().id(2)
                InstallHelperView().id(3)
            }
            HStack {
                OnboardingButton(title: "Previous", isLoading: false, action: { model.previousAction() })
                    .opacity(model.index != 0 ? 1 : 0)
                    .animation(.spring(), value: model.index)
                    .disabled(model.isLoading)

                Spacer()
                OnboardingButton(
                    title: nextButtonTitle,
                    isLoading: model.isLoading,
                    action: { model.nextAction() }
                )
                .disabled(model.isLoading)
                .animation(.spring(), value: model.index)
            }.overlay(alignment: .center) {
                PageControl(count: model.numberOfPages, index: $model.index)
            }
        }
        .padding(20)
        .alert(
            "Helper (still) not installed",
            isPresented: Binding<Bool>(
                get: { model.helperError != nil },
                set: { _ in model.helperError = nil }
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
        .preferredColorScheme(.dark)
        .frame(width: 420, height: 600)
    }

    var nextButtonTitle: String {
        switch model.index {
        case 0:
            return "Get started"
        case 3:
            return "Install Helper"
        default:
            return "Next"
        }
    }
}

extension Onboarding {
    final class Model: ObservableObject {
        let didInstallHelper: () -> Void
        @MainActor @Published var index: Int = 0
        @MainActor @Published var helperError: NSError?
        @MainActor @Published var isLoading: Bool = false
        let numberOfPages = 4
        @Dependency(\.helperManager) private var helperManager
        @Dependency(\.launchAtLogin) private var launchAtLogin

        init(didInstallHelper: @escaping () -> Void) {
            self.didInstallHelper = didInstallHelper
        }

        @MainActor
        func nextAction() {
            switch index {
            case 3:
                Task {
                    @MainActor
                    func observeHelperStatus(error: Error?) async {
                        var counter = 0
                        for await status in helperManager.observeHelperStatus() {
                            if status == .enabled {
                                try? await helperManager.installHelper()
                                self.helperError = nil
                                didInstallHelper()
                                break
                            } else if let error, counter == 7 {
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
            case 2:
                launchAtLogin.launchAtLogin(Defaults[.launchAtLogin])
                index += 1
            default:
                index += 1
            }
        }

        @MainActor
        func previousAction() {
            index -= 1
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding(didInstallHelper: {})
            .frame(width: 420, height: 600)
    }
}
