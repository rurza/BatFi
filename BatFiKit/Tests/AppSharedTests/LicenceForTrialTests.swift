//
//  LicenceForTrialTests.swift
//  BatFi
//
//  The trial asks the server only when told no valid licence is held. A licence found in the
//  keychain but not yet re-checked was told "not valid", so at a launch whose first keychain
//  read failed, a licence due for its re-check let the trial send this Mac's fingerprint to
//  the server once while the re-check ran. A stored licence is "not valid" only once ruled out.
//

import Testing

@testable import Shared

@Suite struct LicenceForTrialTests {
    private func answer(held: Bool = false, stored: StoredLicence, ruledOut: Bool = false) -> Bool? {
        LicenceForTrial.isValid(licenceIsHeld: held, storedLicence: stored, storedLicenceRuledOut: ruledOut)
    }

    // MARK: The hole

    /// The launch read threw; the second read found a licence past its refresh, and its
    /// re-check is still running. Also while a key typed meanwhile is checked or refused.
    @Test func aStoredLicenceNotYetJudgedIsNotKnown() {
        #expect(answer(stored: .present) == nil)
    }

    // MARK: Known answers

    @Test func beforeTheKeychainIsReadNothingIsKnown() {
        #expect(answer(stored: .notKnown) == nil)
    }

    @Test func nothingStoredIsNotValid() {
        #expect(answer(stored: .none) == false)
    }

    @Test func aHeldLicenceIsValid() {
        #expect(answer(held: true, stored: .present) == true)
        // A key verified before the keychain answered.
        #expect(answer(held: true, stored: .notKnown) == true)
    }

    /// The re-check got a definite "no", the server returned another key's licence, or the item
    /// cannot be turned into a licence: the Mac is unlicensed, and an ended trial is still
    /// asked about — also once the error shown for it is dismissed.
    @Test func aStoredLicenceRuledOutIsNotValid() {
        #expect(answer(stored: .present, ruledOut: true) == false)
    }

    @Test func aKeyVerifiedOverALicenceRuledOutIsValid() {
        #expect(answer(held: true, stored: .present, ruledOut: true) == true)
    }
}
