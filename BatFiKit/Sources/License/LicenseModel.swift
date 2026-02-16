//
//  File.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import AppKit
import Clients
@preconcurrency import Combine
import Dependencies
import Shared

@MainActor
public final class LicenseModel: ObservableObject {
    @Published
    public var license: String = ""

    @Published
    public private(set) var state: AsyncResource<License?> = .initial

    @Dependency(\.licenseClient)
    private var licenseClient

    @Dependency(\.keychainClient)
    private var keychainClient

    weak var existingLicenseWindow: NSWindow?

    private(set) var onboardingLicenseViewVisible = false

    public var hasValidLicense: Bool {
        state.license != nil
    }

    public var canVerifyLicense: Bool { !license.isEmpty }

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
        guard state != .loading && state.license == nil else { return }
        openLicenseWindowIfNotOpened()
        state = .loading
        do {
            let license = try await licenseClient.checkLicense(key: license)
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
            guard license.refreshDate.timeIntervalSinceNow < -60 * 60 * 24 * 10 else {
                state = .loaded(license)
                return true
            }
            do {
                let fetchedLicense = try await licenseClient.checkLicense(key: license.key)
                if fetchedLicense.key == license.key  {
                    state = .loaded(license)
                    return true
                } else {
                    try await keychainClient.saveLicense(nil)
                    state = .loaded(nil)
                    return false
                }
            } catch {
                if error is URLError {
                    state = .loaded(license)
                    return true
                } else {
                    state = .error(error as NSError)
                }
            }
        } catch {
            state = .error(error as NSError)
        }
        return false
    }
    
    public func removeLicense() {
        Task {
            try await keychainClient.saveLicense(nil)
            state = .initial
        }
    }

    private func openLicenseWindowIfNotOpened() {
        guard existingLicenseWindow == nil && !onboardingLicenseViewVisible else { return }
        openLicenseWindow()
    }

    @MainActor
    public func openLicenseWindow() {
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
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

    public func licenseViewOnOnboardingVisibilityDidChange(isVisible: Bool) {
        onboardingLicenseViewVisible = isVisible
    }

    public func stateChanges() -> AsyncStream<AsyncResource<License?>> {
        AsyncStream { continuation in
            let cancellable = $state.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

extension AsyncResource where Resource == License? {
    public var license: License? {
        switch self {
        case .loaded(let resource):
            return resource
        default:
            return nil
        }
    }
}
