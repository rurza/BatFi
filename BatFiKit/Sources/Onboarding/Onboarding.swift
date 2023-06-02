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

    init(didTapInstallHelper: @escaping () -> Void) {
        _model = StateObject(wrappedValue: Model(didTapInstallHelper: didTapInstallHelper))
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
                Button(
                    action: {
                        model.previousAction()
                    }
                ) {
                    Text("Previous")
                }
                .buttonStyle(.onboarding)
                .opacity(model.index != 0 ? 1 : 0)
                .animation(.spring(), value: model.index)

                Spacer()

                Button(
                    action: {
                        model.nextAction()
                    }
                ) {
                    switch model.index {
                    case 0:
                        Text("Get started")
                    case 3:
                        Text("Install Helper")
                    default:
                        Text("Next")
                    }
                }
                .buttonStyle(.onboarding)
                .animation(.spring(), value: model.index)
            }.overlay(alignment: .center) {
                PageControl(count: model.numberOfPages, index: $model.index)
            }
        }
        .padding(20)
        .alert(
            "Helper error",
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
                Text("Keep in mind that the app won't work without the helper tool. Please open System Settings and give the app permission.")
            }
        )
//        .preferredColorScheme(.dark)
        .frame(width: 420, height: 600)
    }
}

extension Onboarding {
    final class Model: ObservableObject {
        let didTapInstallHelper: () -> Void
        @Published var index: Int = 0
        @Published var helperError: NSError?
        let numberOfPages = 4
        @Dependency(\.helperManager) private var helperManager
        @Dependency(\.launchAtLogin) private var launchAtLogin

        init(didTapInstallHelper: @escaping () -> Void) {
            self.didTapInstallHelper = didTapInstallHelper
        }

        func nextAction() {
            switch index {
            case 3:
                Task { @MainActor in
                    do {
                        try await helperManager.installHelper()
                        didTapInstallHelper()
                    } catch {
                        helperError = error as NSError
                    }
                }
            case 2:
                launchAtLogin.launchAtLogin(Defaults[.launchAtLogin])
                index += 1
            default:
                index += 1
            }
        }

        func previousAction() {
            index -= 1
        }
    }
}

struct Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        Onboarding(didTapInstallHelper: {})
            .frame(width: 420, height: 600)
    }
}
