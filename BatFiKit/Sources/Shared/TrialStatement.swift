//
//  TrialStatement.swift
//  BatFi
//
//  The free trial as the licence server signs it.
//

import Foundation

/// The claims of a signed trial statement
/// (the free-trial wire spec).
///
/// `startedAt` and `endsAt` are fixed when the trial is created; `confirmedAt` is the
/// server's clock when it last answered.
public struct TrialStatement: Equatable, Sendable {
    public let app: String
    public let kind: String
    public let computerID: String
    public let startedAt: Date
    public let endsAt: Date
    public let confirmedAt: Date

    public init(app: String, kind: String, computerID: String, startedAt: Date, endsAt: Date, confirmedAt: Date) {
        self.app = app
        self.kind = kind
        self.computerID = computerID
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.confirmedAt = confirmedAt
    }

    /// Decodes the statement's JSON claims. Every claim is required, and every time must be
    /// RFC 3339 in UTC, whole seconds, with the `Z` suffix.
    public init(claims: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: claims)
    }

    /// Whether the statement was made for this app, as a trial, for the Mac with
    /// `fingerprint`. A statement copied from another Mac or app is not.
    public func isValid(forFingerprint fingerprint: String) -> Bool {
        kind == "trial" && app == TrialRequest.app && computerID == fingerprint
    }

    /// The time to judge this statement at: the clock, or the server's last answer when the
    /// clock is behind it. `confirmedAt` is signed, so it is a lower bound on the real time: a
    /// clock turned back cannot give back days that had already passed when the server last
    /// answered, and a re-ask that answers after the end ends the trial whatever the clock
    /// says. Everything that judges a statement by time goes through this.
    public func judgingTime(now: Date) -> Date {
        max(now, confirmedAt)
    }

    /// Whether to ask the server again: its last answer is more than a day old, or is later
    /// than `now`, which means the clock was turned back. The server's answer replaces a
    /// stored statement, and that is what undoes a turned-back clock.
    public func needsReconfirming(now: Date) -> Bool {
        let age = now.timeIntervalSince(confirmedAt)
        return age > 24 * 60 * 60 || age < 0
    }
}

extension TrialStatement: Decodable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            app: try container.decode(String.self, forKey: .app),
            kind: try container.decode(String.self, forKey: .kind),
            computerID: try container.decode(String.self, forKey: .computerID),
            startedAt: try Self.time(.startedAt, in: container),
            endsAt: try Self.time(.endsAt, in: container),
            confirmedAt: try Self.time(.confirmedAt, in: container)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case app
        case kind
        case computerID = "computer_id"
        case startedAt = "started_at"
        case endsAt = "ends_at"
        case confirmedAt = "confirmed_at"
    }

    private static func time(_ key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        let text = try container.decode(String.self, forKey: key)
        // `ISO8601DateFormatter` alone also takes other offsets than `Z`.
        guard text.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/) != nil,
              let date = ISO8601DateFormatter().date(from: text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Not an RFC 3339 UTC time in whole seconds: \(text)"
            )
        }
        return date
    }
}
