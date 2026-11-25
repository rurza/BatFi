//
//  UnlockModel.swift
//  BatFi
//
//  Whether BatFi's features run: a valid licence or a running trial.
//

@preconcurrency import Combine
import Foundation
import Shared

/// Whether BatFi's features run, from the licence and the trial together — the one answer
/// charge management, the energy features and every "working app or activate" choice act on.
/// See `LicenseStatus.unlocking(licence:trial:)`.
///
/// The licence is read with `LicenseStatus.reading(_:)` over every state the model goes
/// through from launch, so "not read yet" is told apart from "removed" as before.
@MainActor
public final class UnlockModel: ObservableObject {
    @Published
    public private(set) var status: LicenseStatus = .unknown

    /// The features run. False while either answer is still being read.
    public var isUnlocked: Bool { status == .valid }

    /// Create it with the models, before either has had a chance to change: the licence is
    /// read from its first state.
    public init(licenseModel: LicenseModel, trialModel: TrialModel) {
        licenseModel.$state
            .scan(LicenseStatus.unknown) { $0.reading($1) }
            .combineLatest(trialModel.$status)
            .map { LicenseStatus.unlocking(licence: $0, trial: $1) }
            .removeDuplicates()
            .assign(to: &$status)
    }

    /// The status now, then each change.
    public func statusChanges() -> AsyncStream<LicenseStatus> {
        AsyncStream { continuation in
            let cancellable = $status.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
