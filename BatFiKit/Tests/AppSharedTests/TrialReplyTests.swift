//
//  TrialReplyTests.swift
//  BatFi
//
//  Asking the licence server for a trial ends in one of three failures the caller can act on
//  — too many new trials from this network, a request the server refused, or anything else —
//  or in a statement that is stored. A statement that is not this Mac's is never stored: it
//  would sit in the keychain as a trial this Mac does not have.
//

import Foundation
import Testing

@testable import AppShared
@testable import Shared

@Suite struct TrialReplyTests {
    private let here = TrialFingerprint.of(serial: "C02TESTSERIAL")

    private func claims(app: String = "BatFi", kind: String = "trial", computerID: String? = nil) -> Data {
        Data("""
        {"app":"\(app)","kind":"\(kind)","computer_id":"\(computerID ?? here)","started_at":"2026-11-13T09:30:00Z","ends_at":"2026-11-20T09:30:00Z","confirmed_at":"2026-11-14T08:00:00Z"}
        """.utf8)
    }

    /// Stands in for the signature check: the "token" is the claims themselves.
    private func trusting(_ token: String) throws -> Data { Data(token.utf8) }

    private struct BadSignature: Error {}
    private func rejecting(_ token: String) throws -> Data { throw BadSignature() }

    private func reply(
        status: Int = 200,
        body: Data,
        verify: (String) throws -> Data
    ) -> Result<TrialReply, TrialRequestFailure> {
        Result { () throws(TrialRequestFailure) in
            try TrialReply(status: status, body: body, fingerprint: here, verify: verify)
        }
    }

    // MARK: Status

    @Test func okIsNotAFailure() {
        #expect(TrialRequestFailure(status: 200) == nil)
    }

    @Test func tooManyRequestsIsThrottled() {
        #expect(TrialRequestFailure(status: 429) == .throttled)
    }

    @Test func badRequestIsRefused() {
        #expect(TrialRequestFailure(status: 400) == .refused)
    }

    @Test(arguments: [201, 204, 301, 401, 403, 404, 500, 502, 503])
    func anyOtherStatusIsUnavailable(status: Int) {
        #expect(TrialRequestFailure(status: status) == .unavailable)
    }

    // MARK: Other errors

    @Test func aNetworkErrorIsUnavailable() {
        #expect(TrialRequestFailure(URLError(.notConnectedToInternet)) == .unavailable)
        #expect(TrialRequestFailure(URLError(.timedOut)) == .unavailable)
    }

    @Test func aTrialFailureStaysWhatItIs() {
        #expect(TrialRequestFailure(TrialRequestFailure.throttled) == .throttled)
        #expect(TrialRequestFailure(TrialRequestFailure.refused) == .refused)
    }

    @Test func anyOtherErrorIsUnavailable() {
        #expect(TrialRequestFailure(BadSignature()) == .unavailable)
    }

    @Test func everyFailureHasAMessage() {
        for failure in [TrialRequestFailure.throttled, .refused, .unavailable] {
            #expect(failure.errorDescription?.isEmpty == false)
        }
        #expect(TrialRequestFailure.throttled.errorDescription != TrialRequestFailure.unavailable.errorDescription)
    }

    // MARK: Reply

    @Test func aStatementForThisMacIsKeptWithItsToken() throws {
        let body = claims()
        let accepted = try reply(body: body, verify: trusting).get()
        #expect(accepted.token == String(decoding: body, as: UTF8.self))
        #expect(accepted.statement.computerID == here)
        #expect(accepted.statement.endsAt == ISO8601DateFormatter().date(from: "2026-11-20T09:30:00Z"))
    }

    @Test(arguments: [(429, TrialRequestFailure.throttled), (400, .refused), (500, .unavailable)])
    func aFailedStatusGivesNothingToStore(status: Int, failure: TrialRequestFailure) {
        #expect(reply(status: status, body: claims(), verify: trusting) == .failure(failure))
    }

    @Test func aReplyThatDoesNotVerifyGivesNothingToStore() {
        #expect(reply(body: claims(), verify: rejecting) == .failure(.unavailable))
    }

    @Test func aReplyThatDoesNotDecodeGivesNothingToStore() {
        #expect(reply(body: Data(#"{"app":"BatFi"}"#.utf8), verify: trusting) == .failure(.unavailable))
    }

    @Test func aReplyThatIsNotTextGivesNothingToStore() {
        #expect(reply(body: Data([0xFF, 0xFE, 0x00]), verify: trusting) == .failure(.unavailable))
    }

    @Test func anotherMacsStatementGivesNothingToStore() {
        let body = claims(computerID: TrialFingerprint.of(serial: "C02OTHERMAC"))
        #expect(reply(body: body, verify: trusting) == .failure(.unavailable))
    }

    @Test func anotherAppsStatementGivesNothingToStore() {
        #expect(reply(body: claims(app: "OtherApp"), verify: trusting) == .failure(.unavailable))
    }

    @Test func anotherKindOfStatementGivesNothingToStore() {
        #expect(reply(body: claims(kind: "licence"), verify: trusting) == .failure(.unavailable))
    }

    // MARK: Stored

    @Test func aStoredTokenReadsBackAsItsStatement() {
        let token = String(decoding: claims(), as: UTF8.self)
        #expect(TrialReply.storedStatement(token: token, verify: trusting)?.computerID == here)
    }

    @Test func aStoredTokenThatNoLongerVerifiesIsAbsent() {
        let token = String(decoding: claims(), as: UTF8.self)
        #expect(TrialReply.storedStatement(token: token, verify: rejecting) == nil)
    }

    @Test func aStoredTokenThatNoLongerDecodesIsAbsent() {
        #expect(TrialReply.storedStatement(token: "{}", verify: trusting) == nil)
    }
}
