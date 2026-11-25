//
//  ChargeManagementLicenceTests.swift
//  BatFi
//
//  What charge management does with the licence on each pass. It used to read only "valid
//  or not", so a pass that ran before the keychain had been read at launch handed charging
//  back to macOS — releasing BatFi's limit — and the licence arriving a moment later had to
//  apply it again from nothing.
//

import Foundation
import Testing

@testable import Shared

@Suite struct ChargeManagementLicenceTests {
    private typealias State = AsyncResource<String?>

    @Test func aValidLicenceManagesCharging() {
        #expect(LicenseStatus.valid.chargeManagement == .manage)
    }

    /// Not read yet: nothing is applied, and nothing is handed back either.
    @Test func aLicenceNotReadYetWaits() {
        #expect(LicenseStatus.unknown.chargeManagement == .waitForLicence)
    }

    @Test func aLicenceKnownNotToBeValidHandsChargingBack() {
        #expect(LicenseStatus.invalid.chargeManagement == .handBack)
    }

    /// The launch that released the limit: the first passes run while the model is still
    /// `.initial`, and the licence arrives after them. None of those passes hands back.
    @Test func aLaunchThatOutrunsTheKeychainNeverHandsBack() {
        var status = LicenseStatus.unknown
        var decisions: [LicenseStatus.ChargeManagement] = []
        for state in [State.initial, .initial, .loaded("key")] {
            status = status.reading(state)
            decisions.append(status.chargeManagement)
        }
        #expect(!decisions.contains(.handBack))
        #expect(decisions.last == .manage)
    }

    /// No licence in the keychain is still handed back once it is known.
    @Test func aLaunchWithNoLicenceHandsBackOnceItIsKnown() {
        let status = LicenseStatus.unknown.reading(State.loaded(nil))
        #expect(status.chargeManagement == .handBack)
    }

    /// A licence removed while running is not "not read yet": it hands back at once.
    @Test func aLicenceRemovedWhileRunningHandsBack() {
        let status = LicenseStatus.valid.reading(State.initial)
        #expect(status.chargeManagement == .handBack)
    }
}
