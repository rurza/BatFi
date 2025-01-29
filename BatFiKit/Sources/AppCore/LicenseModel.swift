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
public final class LicenseModel: ObservableObject {
    @Published
    public var email: String = ""
    @Published
    public var license: String = ""

    @Published
    public private(set) var state: AsyncResource<License?> = .initial

    @Dependency(\.licenseClient)
    private var licenseClient

    @Dependency(\.keychainClient)
    private var keychainClient

    weak var existingLicenseWindow: NSWindow?

    public var hasValidLicense: Bool {
        state.license != nil
    }

    public var canVerifyLicense: Bool {
        !email.isEmpty && !license.isEmpty
    }

    public init() {
        Task {
            let license = try await licenseClient.cachedLicense()
            guard let license else {
                return
            }
            state = .loaded(license)
        }
    }

    public func lostLicenseButtonClicked() {
        NSWorkspace.shared.open(URL(string: "https://micropixels.software/apps/batfi#faq")!)
    }

    public func verifyLicenseButtonClicked() {
        Task {
            await asyncVerifyLicense()
        }
    }

    public func asyncVerifyLicense() async {
        guard canVerifyLicense else { return }
        guard state != .loading else { return }
        state = .loading
        do {
            let license = try await licenseClient.checkLicense(email: email, key: license)
            state = .loaded(license)
        } catch {
            state = .error(error as NSError)
        }
    }

    public func verifyCachedLicense() async -> Bool {
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
                    try? await keychainClient.saveLicense(nil)
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

    public func openLicenseWindow() {
        if let existingLicenseWindow {
            existingLicenseWindow.makeKeyAndOrderFront(nil)
        } else {
            let window = LicenseWindow(model: self)
            window.makeKeyAndOrderFront(nil)
            window.center()
            existingLicenseWindow = window
        }
    }

    public func purchaseLicenseButtonClicked() {
        NSWorkspace.shared.open(URL(string: "https://micropixels.software/batfi")!)
    }

    public func dimissErrorClicked() {
        state = .initial
    }
}

extension AsyncResource where Resource == License? {
    var license: License? {
        switch self {
        case .loaded(let resource):
            return resource
        default:
            return nil
        }
    }
}
