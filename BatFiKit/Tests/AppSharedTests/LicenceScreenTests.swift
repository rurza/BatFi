//
//  LicenceScreenTests.swift
//  BatFi
//
//  What the screens that talk about the licence show. A valid licence shows no trial wording
//  whatever the trial's state, and a licence that is stored, or may be, keeps the screens as
//  they are today: the trial is offered only where the app knows nothing is stored and no trial
//  has been held here.
//

import Foundation
import Testing

@testable import Shared

@Suite struct LicenceScreenTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let ends = now.addingTimeInterval(3 * 86400 - 60)
    private static let ended = now.addingTimeInterval(-86400)

    private static let stored: [StoredLicence] = [.notKnown, .none, .present]
    private static let trials: [TrialStatus] = [.notKnown, .none, .running(until: ends), .ended(at: ended)]

    private func screen(
        valid: Bool = false,
        stored: StoredLicence,
        trial: TrialStatus,
        starting: Bool = false
    ) -> LicenceScreen {
        LicenceScreen(
            licenceIsValid: valid,
            storedLicence: stored,
            trial: trial,
            isStartingTrial: starting,
            now: Self.now
        )
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let stored: StoredLicence
        let trial: TrialStatus
        let starting: Bool
        let shows: LicenceScreen
        var testDescription: String { "stored \(stored), trial \(trial), starting \(starting) → \(shows)" }
    }

    /// Every input without a valid licence.
    static let table: [Row] = [false, true].flatMap { starting in [
        Row(stored: .notKnown, trial: .notKnown, starting: starting, shows: .undetermined),
        Row(stored: .notKnown, trial: .none, starting: starting, shows: .undetermined),
        Row(stored: .notKnown, trial: .running(until: ends), starting: starting, shows: .undetermined),
        Row(stored: .notKnown, trial: .ended(at: ended), starting: starting, shows: .undetermined),

        Row(stored: .present, trial: .notKnown, starting: starting, shows: .activateOnly),
        Row(stored: .present, trial: .none, starting: starting, shows: .activateOnly),
        Row(stored: .present, trial: .running(until: ends), starting: starting, shows: .activateOnly),
        Row(stored: .present, trial: .ended(at: ended), starting: starting, shows: .activateOnly),

        Row(stored: .none, trial: .notKnown, starting: starting, shows: .undetermined),
        Row(stored: .none, trial: .none, starting: starting, shows: .offerTrial(isStarting: starting)),
        Row(stored: .none, trial: .running(until: ends), starting: starting, shows: .trialRunning(until: ends, daysLeft: 3)),
        Row(stored: .none, trial: .ended(at: ended), starting: starting, shows: .trialEnded(at: ended)),
    ] }

    @Test(arguments: table)
    func withoutAValidLicence(_ row: Row) {
        #expect(screen(stored: row.stored, trial: row.trial, starting: row.starting) == row.shows)
    }

    @Test func aValidLicenceIsAlwaysLicensed() {
        for stored in Self.stored {
            for trial in Self.trials {
                for starting in [false, true] {
                    #expect(screen(valid: true, stored: stored, trial: trial, starting: starting) == .licensed)
                }
            }
        }
    }

    @Test func noTrialWordingWhereALicenceIsOrMayBeStored() {
        for valid in [false, true] {
            for stored in [StoredLicence.notKnown, .present] {
                for trial in Self.trials {
                    for starting in [false, true] {
                        let shows = screen(valid: valid, stored: stored, trial: trial, starting: starting)
                        #expect(!shows.talksAboutTheTrial, "\(stored), \(trial) showed \(shows)")
                    }
                }
            }
        }
    }

    @Test func theTrialIsOfferedOnlyWithNothingStoredAndNoTrialHeld() {
        for valid in [false, true] {
            for stored in Self.stored {
                for trial in Self.trials {
                    for starting in [false, true] {
                        guard case .offerTrial = screen(valid: valid, stored: stored, trial: trial, starting: starting) else { continue }
                        #expect(!valid && stored == .none && trial == .none)
                    }
                }
            }
        }
    }

    // MARK: Onboarding's key field

    @Test(arguments: [
        LicenceScreen.undetermined, .activateOnly, .offerTrial(isStarting: false),
        .offerTrial(isStarting: true), .trialEnded(at: ended),
    ])
    func onboardingAsksForAKeyWhereverTheAppIsNotLicensedOrInATrialItConfirmed(_ shows: LicenceScreen) {
        // Including `.activateOnly` while a trial runs underneath and unlocks the app: a key
        // typed there is a customer who bought during the trial, and must be checked.
        #expect(shows.onboardingAsksForAKey)
    }

    @Test(arguments: [LicenceScreen.licensed, .trialRunning(until: ends, daysLeft: 3)])
    func onboardingConfirmsInsteadOfAskingForAKey(_ shows: LicenceScreen) {
        #expect(!shows.onboardingAsksForAKey)
    }

    // MARK: Onboarding's primary button

    @Test(arguments: [false, true])
    func onboardingStartsTheOfferedTrialWithNoKeyTyped(_ starting: Bool) {
        #expect(
            LicenceScreen.offerTrial(isStarting: starting).onboardingButton(hasTypedText: false, isUnlocked: false)
                == .startTrial(isStarting: starting)
        )
    }

    @Test(arguments: [false, true])
    func onboardingActivatesAKeyTypedBesideTheOfferedTrial(_ starting: Bool) {
        #expect(
            LicenceScreen.offerTrial(isStarting: starting).onboardingButton(hasTypedText: true, isUnlocked: false)
                == .activate(isEnabled: true)
        )
    }

    /// Every screen but the offered trial keeps today's button: Activate, enabled once a key is
    /// typed, and Next where the app is unlocked and no key is typed or asked for.
    static let todaysButtons: [(LicenceScreen, Bool, Bool, OnboardingLicenceButton)] = [
        (.undetermined, false, false, .activate(isEnabled: false)),
        (.undetermined, true, false, .activate(isEnabled: true)),
        (.activateOnly, false, false, .activate(isEnabled: false)),
        (.activateOnly, true, false, .activate(isEnabled: true)),
        // A trial running under a stored licence: a typed key is checked, none moves on.
        (.activateOnly, false, true, .next),
        (.activateOnly, true, true, .activate(isEnabled: true)),
        (.trialEnded(at: ended), false, false, .activate(isEnabled: false)),
        (.trialEnded(at: ended), true, false, .activate(isEnabled: true)),
        (.trialRunning(until: ends, daysLeft: 3), false, true, .next),
        (.trialRunning(until: ends, daysLeft: 3), true, true, .next),
        (.licensed, false, true, .next),
        (.licensed, true, true, .next),
    ]

    @Test func everyOtherScreenKeepsTodaysButton() {
        for (shows, typed, unlocked, button) in Self.todaysButtons {
            #expect(
                shows.onboardingButton(hasTypedText: typed, isUnlocked: unlocked) == button,
                "\(shows), typed \(typed), unlocked \(unlocked)"
            )
        }
    }

    @Test func daysLeftAtTheLastMomentIsOne() {
        let shows = screen(stored: .none, trial: .running(until: Self.now.addingTimeInterval(1)))
        #expect(shows == .trialRunning(until: Self.now.addingTimeInterval(1), daysLeft: 1))
    }
}

private extension LicenceScreen {
    var talksAboutTheTrial: Bool {
        switch self {
        case .offerTrial, .trialRunning, .trialEnded: true
        case .licensed, .undetermined, .activateOnly: false
        }
    }
}
