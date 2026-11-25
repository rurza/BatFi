//
//  TrialStatus.swift
//  BatFi
//
//  The free trial as the app holds it for a run.
//

import Foundation

/// The free trial as the app holds it for a run: `TrialStanding` with "not known yet" added,
/// and a statement not valid here folded into `none`.
public enum TrialStatus: Equatable, Sendable {
    /// The stored statement has not been read in this run, or could not be read, or this Mac's
    /// fingerprint could not be produced to judge it by. Like a licence not read yet: nothing
    /// new is taken on for it, nothing held is given back, and no trial is offered.
    case notKnown
    /// No trial on this Mac, as far as it knows: none stored, or one not valid here.
    case none
    /// The trial runs until `until`.
    case running(until: Date)
    /// The trial ended at `at`.
    case ended(at: Date)

    public init(_ standing: TrialStanding) {
        switch standing {
        case .none, .notValidHere:
            self = .none
        case let .running(until):
            self = .running(until: until)
        case let .ended(at):
            self = .ended(at: at)
        }
    }

    /// The stored statement judged for this Mac by the clock. Without this Mac's fingerprint
    /// (its serial could not be read) nothing can be confirmed or ruled out, so the answer is
    /// not known: "not valid here" comes only from comparing two real fingerprints.
    public init(statement: TrialStatement?, fingerprint: String?, now: Date) {
        guard let fingerprint else {
            self = .notKnown
            return
        }
        self.init(TrialStanding(statement: statement, fingerprint: fingerprint, now: now))
    }

    /// When the clock alone next changes the answer: a running trial's end. A timer does not
    /// fire while the Mac sleeps and is not moved by a clock change, so waking and the clock
    /// changing are judged again as well. While running, the judging time is before the end
    /// and the clock is not after the judging time, so this is always ahead of the clock.
    public var nextJudgement: Date? {
        guard case let .running(until) = self else { return nil }
        return until
    }

    /// Whole days left while running, never below 1; nil otherwise. `now` is the held
    /// statement's judging time; see `TrialStanding.daysLeft(now:)`.
    public func daysLeft(now: Date) -> Int? {
        guard case let .running(until) = self else { return nil }
        return TrialStanding.running(until: until).daysLeft(now: now)
    }

    /// Whether to ask the server about the stored statement again: only for a statement held
    /// for this Mac, and only when its re-ask rule says so. With nothing stored, or a statement
    /// copied from another Mac, the server is never asked unprompted — this Mac's fingerprint
    /// leaves it only when the person starts a trial. Nor without this Mac's fingerprint: the
    /// statement cannot be judged, and the request would have nothing to send.
    ///
    /// Never while a licence is valid: a licensed customer's Mac does not keep contacting the
    /// server about a trial. Nor while the licence is not known yet (`licenceIsValid` nil), as
    /// it may be valid; the caller asks again once it is known. An unlicensed Mac keeps asking
    /// about an ended trial once a day, so an extension granted by support is picked up.
    public static func asksServerAgain(stored: TrialStatement?, fingerprint: String?, licenceIsValid: Bool?, now: Date) -> Bool {
        guard licenceIsValid == false else { return false }
        guard let stored, let fingerprint, stored.isValid(forFingerprint: fingerprint) else { return false }
        return stored.needsReconfirming(now: now)
    }
}
