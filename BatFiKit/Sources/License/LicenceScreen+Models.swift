//
//  LicenceScreen+Models.swift
//  BatFi
//
//  What the licence screens show, from the licence and trial models.
//

@preconcurrency import Combine
import Foundation
import Shared

extension LicenceScreen {
    /// What the licence screens show now. A view that observes both models gets a new answer
    /// whenever either changes; days left also move with `now`.
    @MainActor
    public init(licenseModel: LicenseModel, trialModel: TrialModel, now: Date) {
        self.init(
            licenceIsValid: licenseModel.hasValidLicense,
            storedLicence: licenseModel.storedLicence,
            trial: trialModel.status,
            isStartingTrial: trialModel.isStarting,
            now: trialModel.judgingTime(now: now)
        )
    }

    /// What the licence screens show now, then each change, for what is not a view: the
    /// trial's notifications.
    @MainActor
    public static func changes(licenseModel: LicenseModel, trialModel: TrialModel) -> AsyncStream<LicenceScreen> {
        AsyncStream { continuation in
            // From the published values themselves: a model's own properties still hold the
            // old value while its publisher emits.
            let cancellable = licenseModel.$state
                .combineLatest(licenseModel.$storedLicence, trialModel.$status, trialModel.$isStarting)
                .map { state, storedLicence, trial, isStarting in
                    LicenceScreen(
                        licenceIsValid: state.license != nil,
                        storedLicence: storedLicence,
                        trial: trial,
                        isStartingTrial: isStarting,
                        now: trialModel.judgingTime(now: .now)
                    )
                }
                .removeDuplicates()
                .sink { continuation.yield($0) }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
