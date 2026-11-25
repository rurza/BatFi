//
//  File.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import AppKit
import AppShared
import Clients
@preconcurrency import Combine
import Dependencies
import os
import Shared

@MainActor
public final class LicenseModel: ObservableObject {
    @Published
    public var license: String = ""

    @Published
    public private(set) var state: AsyncResource<License?> = .initial

    /// Whether a licence is stored on this Mac, whatever `state` says of its validity.
    @Published
    public private(set) var storedLicence: StoredLicence = .notKnown

    /// The free trial beside the licence, for the licence window: it shows the trial while no
    /// licence is stored.
    public let trialModel: TrialModel

    @Dependency(\.licenseClient)
    private var licenseClient

    @Dependency(\.keychainClient)
    private var keychainClient

    private let logger = Logger(category: "License")

    weak var existingLicenseWindow: NSWindow?

    private(set) var onboardingLicenseViewVisible = false

    private var licenceValidityForTrial: AnyCancellable?

    /// The stored licence was found in this run not to be a valid licence; see
    /// `LicenceForTrial`. Kept when its error is dismissed, and forgotten once the licence is
    /// deleted or a key is verified.
    @Published
    private var storedLicenceRuledOut = false

    public var hasValidLicense: Bool {
        state.license != nil
    }

    /// A key that is nothing but whitespace is no key; see `LicenceKey`.
    public var canVerifyLicense: Bool { !LicenceKey.normalized(license).isEmpty }

    public init(trialModel: TrialModel) {
        self.trialModel = trialModel
        // The trial asks the server about a held statement only while no licence is valid; nil
        // until the licence has been read, and while a stored one is not judged yet, since it
        // may be valid. From the published values themselves: the model's own properties still
        // hold the old value while they emit.
        licenceValidityForTrial = $state
            .combineLatest($storedLicence, $storedLicenceRuledOut)
            .map { state, storedLicence, ruledOut -> Bool? in
                LicenceForTrial.isValid(
                    licenceIsHeld: state.license != nil,
                    storedLicence: storedLicence,
                    storedLicenceRuledOut: ruledOut
                )
            }
            .removeDuplicates()
            .sink { [weak trialModel] isValid in
                trialModel?.licenceValidityChanged(isValid)
            }
        Task {
            // An empty keychain is an answer, and is recorded as one: left at `.initial`, a
            // launch with no licence stayed "not read yet" until something else settled it,
            // and on the onboarding path nothing does. Only from `.initial`, so a key the user
            // verified in the meantime is not overwritten. A read that throws says nothing
            // either way and stays unknown; `verifyCachedLicense()` reads again at launch.
            let license: License?
            do {
                license = try await licenseClient.cachedLicense()
            } catch {
                // A stored item that cannot be turned into a licence is still stored; see
                // `verifyCachedLicense()`.
                guard !(error is KeychainLicenceRead.Failure), state == .initial else { return }
                storedLicenceRuledOut = true
                record(.keychainRead(found: true))
                return
            }
            guard state == .initial else { return }
            state = .loaded(license)
            record(.keychainRead(found: license != nil))
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
        // A key pasted from an email arrives with line breaks or spaces inside it; the
        // field shows the key as it is sent.
        let key = LicenceKey.normalized(license)
        license = key
        openLicenseWindowIfNotOpened()
        state = .loading
        record(.verificationStarted)
        do {
            let license = try await licenseClient.checkLicense(key: key)
            state = .loaded(license)
            record(.keyVerified)
        } catch {
            state = .error(error as NSError)
            record(.verificationFailed)
        }
    }

    public func verifyCachedLicense() async -> Bool {
        do {
            let license = try await licenseClient.cachedLicense()
            record(.keychainRead(found: license != nil))
            guard let license else {
                state = .loaded(nil)
                return false
            }
            guard license.refreshDate.timeIntervalSinceNow < -60 * 60 * 24 * 10 else {
                state = .loaded(license)
                return true
            }
            let fetchedLicense: License
            do {
                fetchedLicense = try await licenseClient.checkLicense(key: license.key)
            } catch {
                // Only the server saying the key is unknown or deactivated gives the licence
                // up; any other failure keeps it, and the re-check runs again on a later
                // launch. See `LicenceRecheck`.
                if LicenceRecheck.givesUpStoredLicence(after: error) {
                    // The one re-check outcome that switches a customer off; the kind only,
                    // never the key.
                    let kind = (error as? LicenceCheckFailure).map { String(describing: $0.kind) } ?? "unknown"
                    logger.notice("Licence re-check gave the stored licence up: \(kind, privacy: .public)")
                    storedLicenceRuledOut = true
                } else {
                    logger.notice("Licence re-check failed, keeping the stored licence: \(error.localizedDescription, privacy: .public)")
                }
                state = LicenceRecheck.state(after: error, storedLicence: license)
                record(.recheckFailed)
                return state.license != nil
            }
            if fetchedLicense.key == license.key  {
                state = .loaded(license)
                return true
            } else {
                do {
                    try await keychainClient.saveLicense(nil)
                    state = .loaded(nil)
                    record(.deleted)
                } catch {
                    // The server returned another key's licence: the stored one is not valid.
                    storedLicenceRuledOut = true
                    state = .error(error as NSError)
                    record(.deletionFailed)
                }
                return false
            }
        } catch let failure as KeychainLicenceRead.Failure {
            // The keychain could not be read, which says nothing about whether a licence is
            // stored. Recorded as an error it would read as "not valid" and hand charging,
            // Low Power Mode and app throttling back over a licence that may well be there,
            // and asking for a key the user already entered would be wrong too. The state is
            // left as it was — at launch, unknown — and no window opens.
            logger.error("Could not read the licence from the keychain: \(failure.description, privacy: .public)")
            record(.keychainUnreadable)
            return true
        } catch {
            // The keychain was read and the item is there, but it could not be turned into a
            // licence: it is still stored.
            storedLicenceRuledOut = true
            state = .error(error as NSError)
            record(.keychainRead(found: true))
        }
        return false
    }
    
    public func removeLicense() {
        Task {
            do {
                try await keychainClient.saveLicense(nil)
                state = .initial
                record(.deleted)
            } catch {
                record(.deletionFailed)
                // The keychain refused the delete, so the key is still on disk. Leaving the
                // state alone keeps the UI honest about that rather than showing an
                // unlicensed app over a license that is still there.
            }
        }
    }

    private func openLicenseWindowIfNotOpened() {
        guard existingLicenseWindow == nil && !onboardingLicenseViewVisible else { return }
        openLicenseWindow()
    }

    @MainActor
    public func openLicenseWindow() {
        activateApp()
        if let existingLicenseWindow {
            existingLicenseWindow.makeKeyAndOrderFront(nil)
        } else {
            let window = LicenseWindow(model: self, trialModel: trialModel)
            window.makeKeyAndOrderFront(nil)
            window.center()
            existingLicenseWindow = window
        }
    }

    public func purchaseLicenseButtonClicked() {
        NSWorkspace.shared.open(URL(string: "https://micropixels.gumroad.com/l/batfi?wanted=true")!)
    }

    public func dimissErrorClicked() {
        state = .initial
        record(.errorDismissed)
    }

    private func record(_ event: StoredLicence.Event) {
        if event == .deleted || event == .keyVerified {
            storedLicenceRuledOut = false
        }
        storedLicence = storedLicence.after(event)
    }

    public func licenseViewOnOnboardingVisibilityDidChange(isVisible: Bool) {
        onboardingLicenseViewVisible = isVisible
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
