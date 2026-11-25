//
//  TrialStatusTests.swift
//  BatFi
//
//  The trial as the app holds it for a run: not known until the keychain has been read, then
//  judged from the stored statement by the clock. The end is acted on when it comes — judged
//  again at the end date, and on wake and clock changes by the same rule — and the server is
//  asked again only about a statement this Mac holds.
//

import Foundation
import Testing

@testable import Shared

@Suite struct TrialStatusTests {
    private let here = TrialFingerprint.of(serial: "C02TESTSERIAL")
    private let ends = ISO8601DateFormatter().date(from: "2026-11-20T09:30:00Z")!
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    private func statement(computerID: String? = nil, confirmedAt: Date? = nil) -> TrialStatement {
        TrialStatement(
            app: "BatFi",
            kind: "trial",
            computerID: computerID ?? here,
            startedAt: ends.addingTimeInterval(-7 * day),
            endsAt: ends,
            confirmedAt: confirmedAt ?? ends.addingTimeInterval(-6 * day)
        )
    }

    private func status(_ statement: TrialStatement?, now: Date) -> TrialStatus {
        TrialStatus(statement: statement, fingerprint: here, now: now)
    }

    // MARK: Judging

    @Test func nothingStoredIsNone() {
        #expect(status(nil, now: ends) == .none)
    }

    @Test func aStatementForAnotherMacCountsAsNone() {
        #expect(status(statement(computerID: TrialFingerprint.of(serial: "OTHER")), now: ends.addingTimeInterval(-day)) == .none)
    }

    @Test func withoutThisMacsFingerprintAHeldStatementIsNotKnown() {
        // The serial could not be read: the statement can be neither confirmed nor ruled out
        // here, so nothing new is taken on and nothing held is given back.
        #expect(TrialStatus(statement: statement(), fingerprint: nil, now: ends.addingTimeInterval(-day)) == .notKnown)
        #expect(TrialStatus(statement: statement(), fingerprint: nil, now: ends.addingTimeInterval(day)) == .notKnown)
    }

    @Test func withoutThisMacsFingerprintNothingStoredIsNotKnownEither() {
        // No offer can be made for a Mac whose fingerprint cannot be produced.
        #expect(TrialStatus(statement: nil, fingerprint: nil, now: ends) == .notKnown)
    }

    @Test func beforeTheEndItIsRunning() {
        #expect(status(statement(), now: ends.addingTimeInterval(-1)) == .running(until: ends))
    }

    @Test func exactlyAtTheEndItHasEnded() {
        #expect(status(statement(), now: ends) == .ended(at: ends))
    }

    @Test func oneSecondAfterTheEndItHasEnded() {
        #expect(status(statement(), now: ends.addingTimeInterval(1)) == .ended(at: ends))
    }

    @Test func aStatementWhoseEndIsPastAtLaunchHasEnded() {
        #expect(status(statement(), now: ends.addingTimeInterval(3 * day)) == .ended(at: ends))
    }

    @Test func wakingAfterTheEndJudgesItEnded() {
        // Running when the Mac went to sleep; the timer for the end did not fire while it slept.
        #expect(status(statement(), now: ends.addingTimeInterval(-hour)) == .running(until: ends))
        #expect(status(statement(), now: ends.addingTimeInterval(9 * hour)) == .ended(at: ends))
    }

    @Test func aClockTurnedBackBehindTheServersLastAnswerIsJudgedAtThatAnswer() {
        // Ended, then the clock is turned back a week: the server's last answer, after the end,
        // is a signed lower bound on the real time, so the trial stays ended...
        let confirmed = ends.addingTimeInterval(day)
        let held = statement(confirmedAt: confirmed)
        let turnedBack = ends.addingTimeInterval(-6 * day)
        #expect(status(held, now: turnedBack) == .ended(at: ends))
        // ...and the server's last answer is later than the clock, so it is asked again.
        #expect(TrialStatus.asksServerAgain(stored: held, fingerprint: here, licenceIsValid: false, now: turnedBack))
    }

    /// Offline, a clock turned back a year: the trial runs, but with no more days left than
    /// remained when the server last answered.
    @Test func aClockAYearBackOfflineHasNoMoreDaysLeftThanAtTheLastAnswer() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        let held = statement(confirmedAt: confirmed)
        let yearBack = confirmed.addingTimeInterval(-365 * day)
        let judged = status(held, now: yearBack)
        #expect(judged == .running(until: ends))
        #expect(judged.daysLeft(now: held.judgingTime(now: yearBack)) == 3)
    }

    @Test func withTheClockAheadOfTheLastAnswerTheClockIsUsed() {
        let confirmed = ends.addingTimeInterval(-6 * day)
        let held = statement(confirmedAt: confirmed)
        let now = ends.addingTimeInterval(-2 * day)
        #expect(held.judgingTime(now: now) == now)
        #expect(status(held, now: now).daysLeft(now: held.judgingTime(now: now)) == 2)
    }

    // MARK: The next judgement

    @Test func aRunningTrialIsJudgedAgainAtItsEnd() {
        #expect(TrialStatus.running(until: ends).nextJudgement == ends)
    }

    /// The clock behind the last answer: the trial is judged at that answer, but the next
    /// judgement is still the end by the clock, after the clock's now — never in the past, so
    /// judging again does not spin. At that moment it has ended.
    @Test func withTheClockBehindTheLastAnswerTheNextJudgementIsStillAhead() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        let held = statement(confirmedAt: confirmed)
        let yearBack = confirmed.addingTimeInterval(-365 * day)
        let next = status(held, now: yearBack).nextJudgement
        #expect(next == ends)
        #expect(next.map { $0 > yearBack } == true)
        #expect(status(held, now: ends).nextJudgement == nil)
    }

    @Test(arguments: [TrialStatus.notKnown, .none, .ended(at: Date(timeIntervalSince1970: 0))])
    func nothingElseIsJudgedAgainByTime(_ status: TrialStatus) {
        #expect(status.nextJudgement == nil)
    }

    // MARK: Days left

    @Test func daysLeftWhileRunningIsNeverBelowOne() {
        let running = TrialStatus.running(until: ends)
        for secondsLeft: TimeInterval in [7 * day, day + 1, day, 1, 0.001, 0, -1, -day] {
            let left = running.daysLeft(now: ends.addingTimeInterval(-secondsLeft))
            #expect((left ?? 0) >= 1, "\(secondsLeft) s left gave \(String(describing: left))")
        }
        #expect(running.daysLeft(now: ends.addingTimeInterval(-7 * day)) == 7)
        #expect(running.daysLeft(now: ends.addingTimeInterval(-hour)) == 1)
    }

    @Test(arguments: [TrialStatus.notKnown, .none, .ended(at: Date(timeIntervalSince1970: 0))])
    func onlyARunningTrialHasDaysLeft(_ status: TrialStatus) {
        #expect(status.daysLeft(now: ends) == nil)
    }

    // MARK: Asking the server again

    @Test func nothingStoredIsNeverAskedAbout() {
        #expect(!TrialStatus.asksServerAgain(stored: nil, fingerprint: here, licenceIsValid: false, now: ends))
    }

    @Test func aStatementForAnotherMacIsNeverAskedAbout() {
        // Asking would send this Mac's fingerprint, which leaves it only when the person starts
        // a trial.
        let other = statement(computerID: TrialFingerprint.of(serial: "OTHER"), confirmedAt: ends.addingTimeInterval(-6 * day))
        #expect(!TrialStatus.asksServerAgain(stored: other, fingerprint: here, licenceIsValid: false, now: ends))
    }

    @Test func withoutThisMacsFingerprintTheServerIsNotAsked() {
        let held = statement(confirmedAt: ends.addingTimeInterval(-6 * day))
        #expect(!TrialStatus.asksServerAgain(stored: held, fingerprint: nil, licenceIsValid: false, now: ends))
    }

    @Test func aRecentAnswerIsNotAskedAgain() {
        let held = statement(confirmedAt: ends.addingTimeInterval(-6 * day))
        #expect(!TrialStatus.asksServerAgain(stored: held, fingerprint: here, licenceIsValid: false, now: ends.addingTimeInterval(-6 * day + hour)))
    }

    @Test func anAnswerOlderThanADayIsAskedAgain() {
        let held = statement(confirmedAt: ends.addingTimeInterval(-6 * day))
        #expect(TrialStatus.asksServerAgain(stored: held, fingerprint: here, licenceIsValid: false, now: ends.addingTimeInterval(-4 * day)))
    }

    @Test func anEndedTrialIsStillAskedAboutOnceADay() {
        // Support may have moved the end date since; only the server's answer says so.
        let held = statement(confirmedAt: ends)
        #expect(TrialStatus.asksServerAgain(stored: held, fingerprint: here, licenceIsValid: false, now: ends.addingTimeInterval(2 * day)))
    }

    /// A licensed customer's Mac never contacts the server about a trial: not about one that
    /// ended, and not about one still running underneath, however stale the answer or however
    /// far the clock was turned back.
    @Test func withAValidLicenceTheServerIsNeverAsked() {
        let endedLongAgo = statement(confirmedAt: ends)
        #expect(!TrialStatus.asksServerAgain(stored: endedLongAgo, fingerprint: here, licenceIsValid: true, now: ends.addingTimeInterval(90 * day)))
        let running = statement(confirmedAt: ends.addingTimeInterval(-6 * day))
        #expect(!TrialStatus.asksServerAgain(stored: running, fingerprint: here, licenceIsValid: true, now: ends.addingTimeInterval(-4 * day)))
        #expect(!TrialStatus.asksServerAgain(stored: endedLongAgo, fingerprint: here, licenceIsValid: true, now: ends.addingTimeInterval(-6 * day)))
    }

    /// Until the licence has been read it may be valid, so the server is not asked yet; the
    /// licence becoming known asks then.
    @Test func whileTheLicenceIsNotKnownTheServerIsNotAsked() {
        let held = statement(confirmedAt: ends)
        #expect(!TrialStatus.asksServerAgain(stored: held, fingerprint: here, licenceIsValid: nil, now: ends.addingTimeInterval(2 * day)))
    }

    /// An unlicensed Mac keeps asking about its ended trial once a day, so an extension granted
    /// by support is picked up.
    @Test func withoutAValidLicenceAnEndedTrialIsStillAskedAbout() {
        let held = statement(confirmedAt: ends)
        #expect(TrialStatus.asksServerAgain(stored: held, fingerprint: here, licenceIsValid: false, now: ends.addingTimeInterval(30 * day)))
    }
}
