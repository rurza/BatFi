//
//  TrialReply.swift
//  BatFi
//
//  What the licence server's answer to a trial request leaves the app to store.
//

import Foundation
import Shared

/// The licence server's answer to `POST /trial`, accepted: the signed token to store and the
/// statement it carries.
///
/// The signature check is passed in as `verify` — the bundled public key and the token code
/// live with the live client — so that what is accepted can be tested without them.
public struct TrialReply: Equatable, Sendable {
    /// The compact JWS exactly as the server sent it; this is what is stored.
    public let token: String
    public let statement: TrialStatement

    /// Accepts an answer only when its status is 200 and its body is a token that verifies,
    /// decodes, and is a trial of this app for the Mac with `fingerprint`. A statement made
    /// for another Mac or app is a failure: stored, it would be a trial this Mac does not have.
    ///
    /// - Parameter verify: the token's payload, thrown unless its signature verifies.
    public init(
        status: Int,
        body: Data,
        fingerprint: String,
        verify: (String) throws -> Data
    ) throws(TrialRequestFailure) {
        if let failure = TrialRequestFailure(status: status) {
            throw failure
        }
        guard let token = String(data: body, encoding: .utf8),
              let statement = Self.storedStatement(token: token, verify: verify),
              statement.isValid(forFingerprint: fingerprint) else {
            throw .unavailable
        }
        self.token = token
        self.statement = statement
    }

    /// The statement a stored token carries, or nil when it no longer verifies or decodes:
    /// such a token is no trial, and reading it again will not change that.
    public static func storedStatement(token: String, verify: (String) throws -> Data) -> TrialStatement? {
        guard let claims = try? verify(token) else { return nil }
        return try? TrialStatement(claims: claims)
    }
}
