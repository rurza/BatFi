//
//  LicenceKeyNormalizationTests.swift
//  BatFi
//
//  Customers paste the licence key from an email, and it arrives with a line break inside
//  it. The server cut the key at the line break, so activation failed for a valid key. The
//  key loses its whitespace before it is sent, and nothing else: a key without its dashes
//  could be a UUID or a Gumroad key, so it is not reformatted.
//

import Foundation
import Testing

@testable import Shared

@Suite struct LicenceKeyNormalizationTests {
    private let gumroadKey = "C66054A0-DE794CCF-9FFF3E75-E45AE000"
    private let uuidKey = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

    // MARK: The failed activation seen in the server logs

    @Test func aLineBreakBeforeTheLastBlockIsRemoved() {
        #expect(LicenceKey.normalized("C66054A0-DE794CCF-9FFF3E75-\nE45AE000") == gumroadKey)
    }

    // MARK: Whitespace goes, wherever it is

    @Test func leadingAndTrailingSpacesAreRemoved() {
        #expect(LicenceKey.normalized("  \(gumroadKey)  ") == gumroadKey)
    }

    @Test func tabsCarriageReturnsAndNonBreakingSpacesAreRemoved() {
        #expect(LicenceKey.normalized("\tC66054A0-DE794CCF-\r\n9FFF3E75-E45AE000\u{00A0}\r\n") == gumroadKey)
    }

    @Test func aUUIDWithWhitespaceInsideComesBackClean() {
        #expect(LicenceKey.normalized(" 3F2504E0-4F89 -41D3-\n9A0C-0305E82C3301\t") == uuidKey)
    }

    @Test(arguments: ["C66054A0-DE794CCF-9FFF3E75-E45AE000", "3F2504E0-4F89-41D3-9A0C-0305E82C3301"])
    func aCorrectKeyIsLeftAlone(key: String) {
        #expect(LicenceKey.normalized(key) == key)
    }

    // MARK: Dashes and case stay as pasted

    @Test func aKeyWithoutDashesStaysWithoutThem() {
        #expect(LicenceKey.normalized("C66054A0DE794CCF9FFF3E75E45AE000") == "C66054A0DE794CCF9FFF3E75E45AE000")
    }

    @Test func aKeyWithoutDashesOnlyLosesItsWhitespace() {
        #expect(LicenceKey.normalized(" C66054A0DE794CCF\n9FFF3E75 E45AE000\n") == "C66054A0DE794CCF9FFF3E75E45AE000")
    }

    @Test(arguments: [
        ("ABCD-1234 \nEFGH", "ABCD-1234EFGH"),
        ("C66054A0-DE794CCF9FFF3E75E45AE000", "C66054A0-DE794CCF9FFF3E75E45AE000"),
        ("c66054a0-de794ccf-9fff3e75-e45ae000", "c66054a0-de794ccf-9fff3e75-e45ae000"),
    ])
    func anyShapeOnlyLosesItsWhitespace(input: String, expected: String) {
        #expect(LicenceKey.normalized(input) == expected)
    }

    @Test(arguments: ["", " ", "\n", " \t\r\n\u{00A0}"])
    func onlyWhitespaceBecomesEmpty(input: String) {
        #expect(LicenceKey.normalized(input) == "")
    }
}
