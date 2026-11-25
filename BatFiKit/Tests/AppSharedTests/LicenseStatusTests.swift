//
//  LicenseStatusTests.swift
//  BatFi
//
//  Unit tests for what the energy features make of the licence model's state: valid,
//  known not to be valid, or not read yet at launch — which takes nothing on and gives
//  nothing back.
//

import Foundation
import Testing

@testable import Shared

@Suite struct LicenseStatusTests {
    private typealias State = AsyncResource<String?>

    private let failure = NSError(domain: "LicenseStatusTests", code: 1)

    // MARK: At launch

    @Test func aLicenceNotReadYetIsUnknown() {
        #expect(LicenseStatus.unknown.reading(State.initial) == .unknown)
        // A key being checked says nothing yet about whether it is valid.
        #expect(LicenseStatus.unknown.reading(State.loading) == .unknown)
    }

    @Test func aLicenceReadAtLaunchIsValid() {
        #expect(LicenseStatus.unknown.reading(State.loaded("key")) == .valid)
    }

    @Test func noLicenceOrOneThatCouldNotBeCheckedIsInvalid() {
        #expect(LicenseStatus.unknown.reading(State.loaded(nil)) == .invalid)
        #expect(LicenseStatus.unknown.reading(State.error(failure)) == .invalid)
    }

    // MARK: Once read

    /// The model goes back to `.initial` when the licence is removed, or an error is
    /// dismissed. After launch that is a licence that is not valid, not one still loading.
    @Test func onceReadTheInitialStateIsNoLicence() {
        #expect(LicenseStatus.valid.reading(State.initial) == .invalid)
        #expect(LicenseStatus.invalid.reading(State.initial) == .invalid)
    }

    /// The model checks a key only when it holds no valid licence.
    @Test func onceReadAKeyBeingCheckedIsNoLicenceYet() {
        #expect(LicenseStatus.invalid.reading(State.loading) == .invalid)
    }

    @Test func aLicenceLostWhileRunningIsInvalid() {
        #expect(LicenseStatus.valid.reading(State.loaded(nil)) == .invalid)
        #expect(LicenseStatus.valid.reading(State.error(failure)) == .invalid)
    }

    @Test func aLicenceActivatedWhileRunningIsValid() {
        #expect(LicenseStatus.invalid.reading(State.loaded("key")) == .valid)
    }

    // MARK: What it allows

    @Test func onlyAValidLicenceTakesAnythingOn() {
        #expect(LicenseStatus.valid.allowsTakingOn)
        #expect(!LicenseStatus.invalid.allowsTakingOn)
        #expect(!LicenseStatus.unknown.allowsTakingOn)
    }

    /// Only a licence known not to be valid gives back what a feature holds; one not read
    /// yet keeps it, so that a launch does not give something back only to take it again a
    /// moment later.
    @Test func onlyALicenceKnownNotToBeValidGivesBack() {
        #expect(LicenseStatus.valid.allowsHolding)
        #expect(LicenseStatus.unknown.allowsHolding)
        #expect(!LicenseStatus.invalid.allowsHolding)
    }
}
