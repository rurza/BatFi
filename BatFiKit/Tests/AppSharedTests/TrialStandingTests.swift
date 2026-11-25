//
//  TrialStandingTests.swift
//  BatFi
//
//  A stored trial is judged offline by the Mac's clock against the signed end date. Only that
//  date passing ends it; a statement made for another app or another Mac is worth nothing
//  here. The server is asked again once a day, and whenever the clock has been turned back
//  behind the server's last answer.
//

import Foundation
import Testing

@testable import Shared

@Suite struct TrialStandingTests {
    private let here = TrialFingerprint.of(serial: "C02TESTSERIAL")
    private let ends = ISO8601DateFormatter().date(from: "2026-11-20T09:30:00Z")!
    private let minute: TimeInterval = 60
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86400

    private func statement(
        app: String = "BatFi",
        kind: String = "trial",
        computerID: String? = nil,
        confirmedAt: Date? = nil
    ) -> TrialStatement {
        TrialStatement(
            app: app,
            kind: kind,
            computerID: computerID ?? here,
            startedAt: ends.addingTimeInterval(-7 * day),
            endsAt: ends,
            confirmedAt: confirmedAt ?? ends.addingTimeInterval(-6 * day)
        )
    }

    private func standing(_ statement: TrialStatement?, now: Date) -> TrialStanding {
        TrialStanding(statement: statement, fingerprint: here, now: now)
    }

    // MARK: Standing

    @Test func noStatementIsNone() {
        #expect(standing(nil, now: ends) == .none)
    }

    @Test func beforeTheEndItIsRunning() {
        #expect(standing(statement(), now: ends.addingTimeInterval(-1)) == .running(until: ends))
    }

    @Test func exactlyAtTheEndItHasEnded() {
        #expect(standing(statement(), now: ends) == .ended(at: ends))
    }

    @Test func afterTheEndItHasEnded() {
        #expect(standing(statement(), now: ends.addingTimeInterval(30 * day)) == .ended(at: ends))
    }

    /// The server's last answer is a signed lower bound on the real time: a statement it
    /// confirmed after the end has ended, whatever the clock says.
    @Test func confirmedAfterTheEndItHasEndedWhateverTheClock() {
        let held = statement(confirmedAt: ends.addingTimeInterval(minute))
        #expect(standing(held, now: ends.addingTimeInterval(-6 * day)) == .ended(at: ends))
        #expect(standing(held, now: ends.addingTimeInterval(-365 * day)) == .ended(at: ends))
    }

    @Test func judgingTimeIsTheLaterOfTheClockAndTheLastAnswer() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        let held = statement(confirmedAt: confirmed)
        #expect(held.judgingTime(now: confirmed.addingTimeInterval(-365 * day)) == confirmed)
        #expect(held.judgingTime(now: confirmed.addingTimeInterval(hour)) == confirmed.addingTimeInterval(hour))
    }

    @Test func anotherKindIsNotValidHere() {
        #expect(standing(statement(kind: "licence"), now: ends.addingTimeInterval(-day)) == .notValidHere)
    }

    @Test func anotherAppIsNotValidHere() {
        #expect(standing(statement(app: "OtherApp"), now: ends.addingTimeInterval(-day)) == .notValidHere)
    }

    @Test func anotherMacsFingerprintIsNotValidHere() {
        let elsewhere = TrialFingerprint.of(serial: "C02OTHERMAC")
        #expect(standing(statement(computerID: elsewhere), now: ends.addingTimeInterval(-day)) == .notValidHere)
    }

    /// Copied from another Mac, an ended trial is still not this Mac's: "ended" would offer
    /// nothing more, but it would claim this Mac had a trial.
    @Test func anotherMacsEndedTrialIsNotValidHere() {
        let elsewhere = TrialFingerprint.of(serial: "C02OTHERMAC")
        #expect(standing(statement(computerID: elsewhere), now: ends.addingTimeInterval(day)) == .notValidHere)
    }

    // MARK: Days left

    private static let daysLeftCases: [(remaining: TimeInterval, days: Int)] = [
        (604_800, 7), // 7 days
        (601_200, 7), // 6 days 23 hours
        (86_400, 1), // 24 hours
        (86_340, 1), // 23 hours 59 minutes
        (600, 1), // 10 minutes
        (1, 1), // 1 second
        (86_401, 2), // a day and a second
    ]

    @Test(arguments: daysLeftCases)
    func daysLeftRoundUp(remaining: TimeInterval, days: Int) {
        let now = ends.addingTimeInterval(-remaining)
        #expect(standing(statement(), now: now).daysLeft(now: now) == days)
    }

    @Test func noDaysAreLeftOnceEnded() {
        #expect(standing(statement(), now: ends).daysLeft(now: ends) == nil)
    }

    @Test func noDaysAreLeftWithoutATrialHere() {
        let now = ends.addingTimeInterval(-day)
        #expect(standing(nil, now: now).daysLeft(now: now) == nil)
        #expect(standing(statement(app: "OtherApp"), now: now).daysLeft(now: now) == nil)
    }

    /// A seven-day trial across the night European clocks go back (2026-10-25) is still 168
    /// hours: a local calendar would make one of its days 25 hours long. The count is of
    /// 24-hour days from the signed instant, so no time zone or calendar enters it.
    @Test func daysLeftCountTwentyFourHourDaysAcrossAClockChange() {
        let end = ISO8601DateFormatter().date(from: "2026-10-29T09:30:00Z")!
        let trial = TrialStatement(
            app: "BatFi", kind: "trial", computerID: here,
            startedAt: end.addingTimeInterval(-7 * day), endsAt: end, confirmedAt: end.addingTimeInterval(-7 * day)
        )
        let atStart = end.addingTimeInterval(-7 * day)
        #expect(standing(trial, now: atStart).daysLeft(now: atStart) == 7)
        let oneHourIn = atStart.addingTimeInterval(hour)
        #expect(standing(trial, now: oneHourIn).daysLeft(now: oneHourIn) == 7)
        let lastDay = end.addingTimeInterval(-23 * hour)
        #expect(standing(trial, now: lastDay).daysLeft(now: lastDay) == 1)
    }

    // MARK: Asking the server again

    @Test func confirmedWithinADayIsNotReAsked() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        #expect(!statement(confirmedAt: confirmed).needsReconfirming(now: confirmed.addingTimeInterval(23 * hour)))
    }

    @Test func confirmedExactlyADayAgoIsNotYetReAsked() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        #expect(!statement(confirmedAt: confirmed).needsReconfirming(now: confirmed.addingTimeInterval(day)))
    }

    @Test func confirmedMoreThanADayAgoIsReAsked() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        #expect(statement(confirmedAt: confirmed).needsReconfirming(now: confirmed.addingTimeInterval(25 * hour)))
    }

    /// The clock was turned back behind the server's last answer.
    @Test func confirmedInTheFutureIsReAsked() {
        let confirmed = ends.addingTimeInterval(-3 * day)
        #expect(statement(confirmedAt: confirmed).needsReconfirming(now: confirmed.addingTimeInterval(-minute)))
    }

    @Test func anEndedTrialIsStillReAskedOnTheSameRule() {
        let confirmed = ends.addingTimeInterval(-day)
        #expect(statement(confirmedAt: confirmed).needsReconfirming(now: ends.addingTimeInterval(2 * day)))
    }
}
