//
//  StoredLicenceTests.swift
//  BatFi
//
//  The licence model answered one question, whether a valid licence is held, and "no" covered
//  a keychain not read yet, a keychain that could not be read, a stored licence whose re-check
//  failed and a key being checked — a paying customer can be in any of them. What is stored is
//  a separate answer, and "none" is given only where the app knows nothing is there.
//

import Testing

@testable import Shared

@Suite struct StoredLicenceTests {
    private func answer(after events: StoredLicence.Event...) -> StoredLicence {
        events.reduce(StoredLicence.notKnown) { $0.after($1) }
    }

    // MARK: Launch

    @Test func nothingIsKnownBeforeTheKeychainIsRead() {
        #expect(answer() == .notKnown)
    }

    @Test func anEmptyKeychainMeansNone() {
        #expect(answer(after: .keychainRead(found: false)) == .none)
    }

    @Test func aFailedReadLeavesItNotKnown() {
        #expect(answer(after: .keychainUnreadable) == .notKnown)
    }

    @Test func aLaterEmptyReadAfterAFailedOneMeansNone() {
        #expect(answer(after: .keychainUnreadable, .keychainRead(found: false)) == .none)
    }

    @Test func aStoredLicenceIsPresent() {
        #expect(answer(after: .keychainRead(found: true)) == .present)
    }

    /// The re-check of a stored licence ending in the model's error state after a 404 or 403
    /// does not delete it: it is still in the keychain.
    @Test func aStoredLicenceWhoseRecheckFailedIsStillPresent() {
        #expect(answer(after: .keychainRead(found: true), .recheckFailed) == .present)
    }

    // MARK: A key entered by hand

    @Test func aVerifiedKeyIsPresent() {
        #expect(answer(after: .keychainRead(found: false), .verificationStarted, .keyVerified) == .present)
    }

    @Test func aFailedVerificationWithNothingStoredLeavesNone() {
        #expect(answer(after: .keychainRead(found: false), .verificationStarted, .verificationFailed) == .none)
    }

    @Test func dismissingTheErrorStillLeavesNone() {
        let answer = answer(after: .keychainRead(found: false), .verificationStarted, .verificationFailed, .errorDismissed)
        #expect(answer == .none)
    }

    @Test(arguments: [StoredLicence.notKnown, .none, .present])
    func aVerificationInFlightKeepsThePreviousAnswer(previous: StoredLicence) {
        #expect(previous.after(.verificationStarted) == previous)
    }

    // MARK: Removal

    @Test func aRemovedLicenceIsNone() {
        #expect(answer(after: .keychainRead(found: true), .deleted) == .none)
    }

    @Test func aRemovalTheKeychainRefusedLeavesItPresent() {
        #expect(answer(after: .keychainRead(found: true), .deletionFailed) == .present)
    }

    /// The re-check returned a licence for another key, and the stored one was deleted.
    @Test func aLicenceDeletedForAKeyMismatchIsNone() {
        #expect(answer(after: .keychainRead(found: true), .deleted) == .none)
    }

    // MARK: Once known, known

    @Test(arguments: [StoredLicence.none, .present])
    func aKnownAnswerSurvivesAFailedRead(known: StoredLicence) {
        #expect(known.after(.keychainUnreadable) == known)
    }
}
