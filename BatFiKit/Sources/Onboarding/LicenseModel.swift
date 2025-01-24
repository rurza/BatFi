//
//  File.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import AppKit
import Clients
import Combine
import Dependencies
import Shared

@MainActor
final class LicenseModel: ObservableObject {

    @Published
    var email: String = ""
    @Published
    var license: String = ""

    @Published
    var state: AsyncResource<License?> = .initial

    var canVerifyLicense: Bool {
        !email.isEmpty && !license.isEmpty
    }

    @Dependency(\.licenseClient)
    private var licenseClient

    func lostLicenseButtonClicked() {
        NSWorkspace.shared.open(URL(string: "https://micropixels.software/apps/batfi#faq")!)
    }

    func verifyLicenseButtonClicked() {
        guard canVerifyLicense else { return }
        guard state != .loading else { return }
        state = .loading
        Task {
            do {
                let license = try await licenseClient.checkLicense(email: email, key: license)
                state = .loaded(license)
            } catch {
                state = .error(error as NSError)
            }
        }
    }

    func verifyCachedLicense() async -> Bool {
        state = .loading
        do {
            let license = try await licenseClient.cachedLicense()
            guard let license else {
                state = .loaded(nil)
                return false
            }
            do {
                let fetchedLicense = try await licenseClient.checkLicense(email: license.email, key: license.key)
                if fetchedLicense == license {
                    state = .loaded(license)
                } else {
                    state = .loaded(nil)
                }
                return license == fetchedLicense
            } catch {
                state = .error(error as NSError)
            }
        } catch {
            state = .error(error as NSError)
        }
        return false
    }

    func purchaseLicenseButtonClicked() {
        NSWorkspace.shared.open(URL(string: "https://micropixels.software/batfi")!)
    }

    func dimissErrorClicked() {
        state = .initial
    }

}
