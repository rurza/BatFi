//
//  TrialNotice.swift
//  BatFi
//
//  The two notifications a trial ever sends: a day before it ends, and when it has ended.
//

import Foundation

/// One of the two notifications a trial ever sends.
public enum TrialNotice: Equatable, Sendable {
    /// 24 hours or less remain.
    case dayBefore
    /// The trial has ended.
    case ended

    /// How long before the end the day-before notice is due.
    public static let dayBeforeLead: TimeInterval = 24 * 60 * 60

    /// What was already sent, each as the end date of the trial it was sent for. A trial given
    /// a new end date (support extended it) is a new trial to these.
    public struct Sent: Equatable, Sendable {
        public var dayBeforeForEnd: Date?
        public var endedForEnd: Date?

        public init(dayBeforeForEnd: Date? = nil, endedForEnd: Date? = nil) {
            self.dayBeforeForEnd = dayBeforeForEnd
            self.endedForEnd = endedForEnd
        }
    }

    public struct Decision: Equatable, Sendable {
        /// The notice to send now, if any.
        public var due: TrialNotice?
        /// When to decide again, the notice due now counted as sent; nil when only a change of
        /// the screen answer can make anything due.
        public var next: Date?

        public init(due: TrialNotice?, next: Date?) {
            self.due = due
            self.next = next
        }
    }

    /// The end date this install has seen a trial running until, once `screen` is shown.
    ///
    /// A valid licence forgets it: a customer who bought during the trial, and months later
    /// removes the licence to move it to another Mac, meets the trial ended — and is not told
    /// it has just ended. A trial still running when the licence goes is seen running again.
    public static func seenRunningUntil(after screen: LicenceScreen, previous: Date?) -> Date? {
        switch screen {
        case let .trialRunning(until, _):
            return until
        case .licensed:
            return nil
        case .undetermined, .activateOnly, .offerTrial, .trialEnded:
            return previous
        }
    }

    /// Which notice is due now, and when to decide again.
    ///
    /// Only the trial screens have notices: anyone with a stored licence, or one that may be
    /// stored, and anyone who has not started a trial, is sent nothing. An ended trial is sent
    /// only its end notice, so a Mac that was off through the last day hears once, not twice;
    /// and only for an end date this install saw running (`seenRunningUntil`). A trial first met
    /// already ended — data wiped, Start pressed, and the server said it had ended — most likely
    /// had its notice on the day, and the screen already says so.
    public static func decision(screen: LicenceScreen, now: Date, sent: Sent, seenRunningUntil: Date?) -> Decision {
        switch screen {
        case let .trialRunning(until, _):
            // Past its end the trial's own judgement is about to say it ended; the end notice
            // waits for that.
            guard now < until else { return Decision(due: nil, next: nil) }
            let dayBeforeAt = until.addingTimeInterval(-dayBeforeLead)
            guard now >= dayBeforeAt else { return Decision(due: nil, next: dayBeforeAt) }
            let due: TrialNotice? = sent.dayBeforeForEnd == until ? nil : .dayBefore
            return Decision(due: due, next: until)
        case let .trialEnded(at):
            let due = seenRunningUntil == at && sent.endedForEnd != at
            return Decision(due: due ? .ended : nil, next: nil)
        case .licensed, .undetermined, .activateOnly, .offerTrial:
            return Decision(due: nil, next: nil)
        }
    }
}
