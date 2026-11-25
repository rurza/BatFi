//
//  KeychainLicenceReadTests.swift
//  BatFi
//
//  The keychain read used to return nil for every failure — a locked keychain, interaction
//  not allowed, a denied prompt — so a failure looked exactly like a Mac with no licence, and
//  once an empty keychain was recorded as "no licence" charge management handed back on it.
//  Only a missing item means no licence now; anything else throws and leaves it unknown.
//

import Foundation
import Security
import Testing

@testable import Shared

@Suite struct KeychainLicenceReadTests {
    @Test func aStoredLicenceIsReturned() throws {
        let data = Data("jwt".utf8)
        #expect(try KeychainLicenceRead.result(status: errSecSuccess, data: data) == "jwt")
    }

    @Test func noItemMeansNoLicence() throws {
        #expect(try KeychainLicenceRead.result(status: errSecItemNotFound, data: nil) == nil)
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled, errSecNotAvailable])
    func aFailedReadThrowsRatherThanReportingNoLicence(status: OSStatus) {
        #expect(throws: KeychainLicenceRead.Failure(status: status)) {
            try KeychainLicenceRead.result(status: status, data: nil)
        }
    }

    /// An item that is there but is not text is an answer — not a usable licence — and
    /// reading it again will not change it.
    @Test func anItemThatIsNotTextIsNoLicence() throws {
        let data = Data([0xFF, 0xFE, 0xFD])
        #expect(try KeychainLicenceRead.result(status: errSecSuccess, data: data) == nil)
    }
}
