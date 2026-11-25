//
//  TrialStatementTests.swift
//  BatFi
//
//  The free trial is a statement the licence server signs: which app, which Mac, when it
//  started and ends, and when the server last said so. These pin the app's side of the wire
//  message (the free-trial wire spec) — the server tests the same
//  samples — and the one-way fingerprint that stands in for the Mac's serial.
//

import CryptoKit
import Foundation
import Testing

@testable import Shared

@Suite struct TrialStatementTests {
    private let sampleFingerprint = "3f2b8c1d9e0a4b5c6d7e8f9012345678abcdef0123456789abcdef0123456789"

    private func date(_ rfc3339: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: rfc3339))
    }

    // MARK: Fingerprint

    @Test func theFingerprintIsTheSHA256OfTheSaltedSerial() {
        let expected = SHA256.hash(data: Data("BatFi-trial-v1:C02TESTSERIAL".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(TrialFingerprint.of(serial: "C02TESTSERIAL") == expected)
    }

    @Test func theFingerprintIs64LowercaseHexCharacters() {
        let fingerprint = TrialFingerprint.of(serial: "C02TESTSERIAL")
        #expect(fingerprint.count == 64)
        #expect(fingerprint.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func differentSerialsGiveDifferentFingerprints() {
        #expect(TrialFingerprint.of(serial: "C02TESTSERIAL") != TrialFingerprint.of(serial: "C02TESTSERIAM"))
    }

    // MARK: Request

    @Test func theRequestBodyIsThePinnedSample() {
        let body = TrialRequest.body(fingerprint: sampleFingerprint)
        #expect(String(decoding: body, as: UTF8.self) == #"{"app":"BatFi","computer_id":"3f2b8c1d9e0a4b5c6d7e8f9012345678abcdef0123456789abcdef0123456789"}"#)
    }

    // MARK: Statement

    @Test func thePinnedClaimsDecode() throws {
        let claims = #"{"app":"BatFi","kind":"trial","computer_id":"3f2b8c1d9e0a4b5c6d7e8f9012345678abcdef0123456789abcdef0123456789","started_at":"2026-11-13T09:30:00Z","ends_at":"2026-11-20T09:30:00Z","confirmed_at":"2026-11-14T08:00:00Z"}"#
        let statement = try TrialStatement(claims: Data(claims.utf8))
        #expect(statement == TrialStatement(
            app: "BatFi",
            kind: "trial",
            computerID: sampleFingerprint,
            startedAt: try date("2026-11-13T09:30:00Z"),
            endsAt: try date("2026-11-20T09:30:00Z"),
            confirmedAt: try date("2026-11-14T08:00:00Z")
        ))
    }

    @Test func theDesignSampleDecodesWithItsLineBreaks() throws {
        let claims = """
        {
          "app": "BatFi",
          "kind": "trial",
          "computer_id": "\(sampleFingerprint)",
          "started_at": "2026-11-13T09:30:00Z",
          "ends_at": "2026-11-20T09:30:00Z",
          "confirmed_at": "2026-11-13T09:30:00Z"
        }
        """
        let statement = try TrialStatement(claims: Data(claims.utf8))
        #expect(statement.confirmedAt == (try date("2026-11-13T09:30:00Z")))
    }

    @Test(arguments: ["app", "kind", "computer_id", "started_at", "ends_at", "confirmed_at"])
    func aMissingClaimDoesNotDecode(claim: String) throws {
        var claims: [String: String] = [
            "app": "BatFi",
            "kind": "trial",
            "computer_id": sampleFingerprint,
            "started_at": "2026-11-13T09:30:00Z",
            "ends_at": "2026-11-20T09:30:00Z",
            "confirmed_at": "2026-11-14T08:00:00Z",
        ]
        claims[claim] = nil
        let data = try JSONEncoder().encode(claims)
        #expect(throws: (any Error).self) { try TrialStatement(claims: data) }
    }

    /// The wire file fixes UTC whole seconds with `Z`; anything else is not the server speaking.
    @Test(arguments: [
        "2026-11-20T10:30:00+01:00",
        "2026-11-20T09:30:00.000Z",
        "2026-11-20 09:30:00Z",
        "2026-11-20",
        "1763631000",
    ])
    func aTimeInAnotherFormatDoesNotDecode(time: String) throws {
        let claims = [
            "app": "BatFi",
            "kind": "trial",
            "computer_id": sampleFingerprint,
            "started_at": "2026-11-13T09:30:00Z",
            "ends_at": time,
            "confirmed_at": "2026-11-14T08:00:00Z",
        ]
        let data = try JSONEncoder().encode(claims)
        #expect(throws: (any Error).self) { try TrialStatement(claims: data) }
    }
}
