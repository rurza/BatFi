//
//  LicenceScreen.swift
//  BatFi
//
//  What the screens that talk about the licence show: the menu notice, the licence window,
//  onboarding's licence step and the licence pane in Settings.
//

import Foundation

/// What the screens that talk about the licence show.
///
/// Unlike `LicenseStatus.unlocking(licence:trial:)`, which says whether the features run, this
/// says why, and keeps a paying customer away from trial wording: a stored licence always wins
/// over a trial, and the trial is offered only where the app knows nothing is stored.
public enum LicenceScreen: Equatable, Sendable {
    /// A valid licence. No trial wording of any kind, whatever the trial's state.
    case licensed
    /// Not known yet whether a licence is stored, or not yet whether a trial is held while
    /// nothing is. Today's screens, with no trial action.
    case undetermined
    /// A licence is stored but not valid. Today's screens, with no trial action or wording,
    /// even while a trial runs underneath and keeps the features on.
    case activateOnly
    /// Nothing stored and no trial held: the trial may be started. `isStarting` while a start
    /// is in flight, for the button to disable itself.
    case offerTrial(isStarting: Bool)
    /// Nothing stored and the trial running until `until`, with `daysLeft` whole days left.
    case trialRunning(until: Date, daysLeft: Int)
    /// Nothing stored and the trial ended at `at`.
    case trialEnded(at: Date)

    public init(
        licenceIsValid: Bool,
        storedLicence: StoredLicence,
        trial: TrialStatus,
        isStartingTrial: Bool,
        now: Date
    ) {
        if licenceIsValid {
            self = .licensed
            return
        }
        switch (storedLicence, trial) {
        case (.notKnown, _), (.none, .notKnown):
            self = .undetermined
        case (.present, _):
            self = .activateOnly
        case (.none, .none):
            self = .offerTrial(isStarting: isStartingTrial)
        case let (.none, .running(until)):
            self = .trialRunning(until: until, daysLeft: trial.daysLeft(now: now) ?? 1)
        case let (.none, .ended(at)):
            self = .trialEnded(at: at)
        }
    }

    /// Onboarding's licence step shows the key field — everywhere but a valid licence and a
    /// trial it confirms. A key typed there is checked by the step's Next, also while a trial
    /// running underneath already unlocks the app (`.activateOnly`): that is a customer who
    /// bought during the trial.
    public var onboardingAsksForAKey: Bool {
        switch self {
        case .licensed, .trialRunning: false
        case .undetermined, .activateOnly, .offerTrial, .trialEnded: true
        }
    }

    /// What the primary button in onboarding's footer does on the licence step.
    ///
    /// With the trial on offer and no key typed it starts the trial, so the step has one primary
    /// action and it is a live one. Everywhere else it is the button it always was: a typed key
    /// is activated, also while a trial already unlocks the app, and with none typed an
    /// unlocked app moves on.
    ///
    /// - Parameters:
    ///   - hasTypedText: the key field is not empty.
    ///   - isUnlocked: the features run, by a licence or a trial.
    public func onboardingButton(hasTypedText: Bool, isUnlocked: Bool) -> OnboardingLicenceButton {
        if case let .offerTrial(isStarting) = self, !hasTypedText {
            return .startTrial(isStarting: isStarting)
        }
        let keyIsTyped = hasTypedText && onboardingAsksForAKey
        if isUnlocked && !keyIsTyped {
            return .next
        }
        return .activate(isEnabled: hasTypedText || isUnlocked)
    }
}

/// The primary button in onboarding's footer on the licence step.
public enum OnboardingLicenceButton: Equatable, Sendable {
    /// Starts the offered trial; busy while the start is in flight.
    case startTrial(isStarting: Bool)
    /// Moves on to the next step.
    case next
    /// Checks the typed key; disabled with nothing to check.
    case activate(isEnabled: Bool)
}
