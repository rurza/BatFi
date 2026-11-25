//
//  UnlockingTests.swift
//  BatFi
//
//  What the features act on: a valid licence or a running trial unlocks the app. Otherwise,
//  while either is still not known, nothing is handed back — a licence known not to be valid
//  with a trial not read yet, or a licence not read yet beside an ended trial, is not "invalid".
//

import Foundation
import Testing

@testable import Shared

@Suite struct UnlockingTests {
    private static let ends = Date(timeIntervalSince1970: 1_800_000_000)

    struct Row: Sendable, CustomTestStringConvertible {
        let licence: LicenseStatus
        let trial: TrialStatus
        let unlocking: LicenseStatus
        var testDescription: String { "licence \(licence), trial \(trial) → \(unlocking)" }
    }

    static let table: [Row] = [
        Row(licence: .unknown, trial: .notKnown, unlocking: .unknown),
        Row(licence: .unknown, trial: .none, unlocking: .unknown),
        Row(licence: .unknown, trial: .running(until: ends), unlocking: .valid),
        Row(licence: .unknown, trial: .ended(at: ends), unlocking: .unknown),

        Row(licence: .valid, trial: .notKnown, unlocking: .valid),
        Row(licence: .valid, trial: .none, unlocking: .valid),
        Row(licence: .valid, trial: .running(until: ends), unlocking: .valid),
        Row(licence: .valid, trial: .ended(at: ends), unlocking: .valid),

        Row(licence: .invalid, trial: .notKnown, unlocking: .unknown),
        Row(licence: .invalid, trial: .none, unlocking: .invalid),
        Row(licence: .invalid, trial: .running(until: ends), unlocking: .valid),
        Row(licence: .invalid, trial: .ended(at: ends), unlocking: .invalid),
    ]

    @Test(arguments: table)
    func theTruthTable(_ row: Row) {
        #expect(LicenseStatus.unlocking(licence: row.licence, trial: row.trial) == row.unlocking)
    }

    @Test func theEndOfARunningTrialWithoutALicenceHandsChargingBack() {
        let before = LicenseStatus.unlocking(licence: .invalid, trial: .running(until: Self.ends))
        let after = LicenseStatus.unlocking(licence: .invalid, trial: .ended(at: Self.ends))
        #expect(before.chargeManagement == .manage)
        #expect(after.chargeManagement == .handBack)
        #expect(!after.allowsHolding)
    }

    @Test func aLicenceStillBeingReadBesideAnEndedTrialHandsNothingBack() {
        let status = LicenseStatus.unlocking(licence: .unknown, trial: .ended(at: Self.ends))
        #expect(status.chargeManagement == .waitForLicence)
        #expect(status.allowsHolding)
    }
}
