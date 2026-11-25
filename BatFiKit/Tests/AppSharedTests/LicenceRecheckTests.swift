//
//  LicenceRecheckTests.swift
//  BatFi
//
//  The re-check of a stored licence used to give it up on any failure but a URLError, so a
//  licence server or Gumroad outage handed charging back to macOS and let the energy
//  features go for a paying customer. Only a definite answer — the key is unknown, or it was
//  deactivated — gives the licence up now; every other failure keeps it until a later launch.
//

import Foundation
import Testing

@testable import Shared

@Suite struct LicenceRecheckTests {
    private typealias State = AsyncResource<String?>

    private func failure(status: Int) -> LicenceCheckFailure {
        LicenceCheckFailure(kind: LicenceCheckFailure.Kind(status: status)!, message: "message")
    }

    // MARK: A definite answer gives the licence up

    @Test func anUnknownKeyGivesTheLicenceUp() {
        #expect(LicenceRecheck.givesUpStoredLicence(after: failure(status: 404)))
    }

    @Test func aDeactivatedKeyGivesTheLicenceUp() {
        #expect(LicenceRecheck.givesUpStoredLicence(after: failure(status: 403)))
    }

    // MARK: Anything else keeps it

    @Test(arguments: [500, 502, 503, 429, 400])
    func anyOtherStatusKeepsTheLicence(status: Int) {
        #expect(!LicenceRecheck.givesUpStoredLicence(after: failure(status: status)))
    }

    /// The live client throws its localized message for a reply it cannot parse, and for the
    /// Mac's serial being unreadable.
    @Test func anUnparseableReplyKeepsTheLicence() {
        #expect(!LicenceRecheck.givesUpStoredLicence(after: "Unexpected response"))
    }

    @Test func aFailedSignatureKeepsTheLicence() {
        struct SignatureFailure: Error {}
        #expect(!LicenceRecheck.givesUpStoredLicence(after: SignatureFailure()))
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .cannotFindHost, .networkConnectionLost, .secureConnectionFailed])
    func aURLErrorKeepsTheLicence(code: URLError.Code) {
        #expect(!LicenceRecheck.givesUpStoredLicence(after: URLError(code)))
    }

    @Test func aTimeoutKeepsTheLicence() {
        #expect(!LicenceRecheck.givesUpStoredLicence(after: URLError(.timedOut)))
    }

    // MARK: Statuses

    @Test func aSuccessfulReplyIsNoFailure() {
        #expect(LicenceCheckFailure.Kind(status: 200) == nil)
    }

    /// The manual-entry path shows the failure's own message, as before.
    @Test func theFailureShowsItsMessage() {
        let failure = LicenceCheckFailure(kind: .unknownKey, message: "Invalid license key")
        #expect(failure.localizedDescription == "Invalid license key")
    }

    // MARK: What the energy features and charge management read

    @Test func aKeptLicenceStillReadsAsValidAfterAFailedRecheck() {
        let state: State = LicenceRecheck.state(after: failure(status: 503), storedLicence: "key")
        #expect(LicenseStatus.valid.reading(state) == .valid)
        #expect(LicenseStatus.unknown.reading(state) == .valid)
        #expect(LicenseStatus.unknown.reading(state).chargeManagement == .manage)
    }

    @Test func aLicenceGivenUpReadsAsInvalid() {
        let state: State = LicenceRecheck.state(after: failure(status: 404), storedLicence: "key")
        #expect(LicenseStatus.valid.reading(state) == .invalid)
        #expect(LicenseStatus.valid.reading(state).chargeManagement == .handBack)
    }
}
