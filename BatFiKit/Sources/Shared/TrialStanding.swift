//
//  TrialStanding.swift
//  BatFi
//
//  Where this Mac's free trial stands, judged offline.
//

import Foundation

/// Where the free trial stands on this Mac, by its clock against the signed end date.
///
/// Only time passing `endsAt` ends a trial here; the server's answer can replace the stored
/// statement, but this judges whatever statement is held. The time is the clock, never earlier
/// than the server's last answer (`TrialStatement.judgingTime(now:)`).
public enum TrialStanding: Equatable, Sendable {
    /// No statement is stored.
    case none
    /// The trial runs until `until`.
    case running(until: Date)
    /// The trial ended at `at`.
    case ended(at: Date)
    /// The statement is not a trial of this app for this Mac — copied from another Mac or app.
    case notValidHere

    public init(statement: TrialStatement?, fingerprint: String, now: Date) {
        guard let statement else {
            self = .none
            return
        }
        guard statement.isValid(forFingerprint: fingerprint) else {
            self = .notValidHere
            return
        }
        let at = statement.judgingTime(now: now)
        self = at < statement.endsAt ? .running(until: statement.endsAt) : .ended(at: statement.endsAt)
    }

    /// Whole 24-hour days left while running, rounded up: 6 days 23 hours left is 7, ten
    /// minutes left is 1. Nil unless running. Pure interval arithmetic, so neither the time
    /// zone nor the calendar changes it. `now` is the statement's judging time
    /// (`TrialStatement.judgingTime(now:)`), so a clock turned back shows no more days than
    /// remained at the server's last answer.
    public func daysLeft(now: Date) -> Int? {
        guard case let .running(ends) = self else { return nil }
        let days = (ends.timeIntervalSince(now) / (24 * 60 * 60)).rounded(.up)
        return max(1, Int(days))
    }
}
