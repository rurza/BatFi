//
//  TrialNoticeTests.swift
//  BatFi
//
//  The two trial notifications: a day before the end and at the end, each at most once per
//  trial, and never for anyone the screens show no trial wording to.
//

import Foundation
import Testing

@testable import Shared

@Suite struct TrialNoticeTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let hour: TimeInterval = 3600

    /// `seenRunningUntil` defaults to the screen's own end: the trial was seen running here.
    private func decide(
        _ screen: LicenceScreen,
        sent: TrialNotice.Sent = .init(),
        seenRunningUntil: Date?? = .none
    ) -> TrialNotice.Decision {
        let seen: Date? = switch seenRunningUntil {
        case let .some(date): date
        case .none: screen.endForTests
        }
        return TrialNotice.decision(screen: screen, now: Self.now, sent: sent, seenRunningUntil: seen)
    }

    private func running(left: TimeInterval) -> (screen: LicenceScreen, end: Date) {
        let end = Self.now.addingTimeInterval(left)
        return (.trialRunning(until: end, daysLeft: 1), end)
    }

    @Test func threeDaysLeftIsQuietUntilADayBeforeTheEnd() {
        let (screen, end) = running(left: 72 * Self.hour)
        #expect(decide(screen) == .init(due: nil, next: end.addingTimeInterval(-24 * Self.hour)))
    }

    @Test func exactlyADayLeftSendsTheDayBeforeNotice() {
        let (screen, end) = running(left: 24 * Self.hour)
        #expect(decide(screen) == .init(due: .dayBefore, next: end))
    }

    @Test func theDayBeforeNoticeIsSentOnce() {
        let (screen, end) = running(left: 23 * Self.hour)
        #expect(decide(screen, sent: .init(dayBeforeForEnd: end)) == .init(due: nil, next: end))
    }

    /// Covers a launch with under a day left and nothing sent while the app was not running.
    @Test func underADayLeftWithNothingSentSendsTheDayBeforeNotice() {
        let (screen, end) = running(left: 2 * Self.hour)
        #expect(decide(screen) == .init(due: .dayBefore, next: end))
    }

    /// The trial's own judgement says when it has ended; a running screen past its end waits
    /// for that rather than saying the trial ends tomorrow.
    @Test func aRunningScreenPastItsEndSendsNothing() {
        let (screen, _) = running(left: -1)
        #expect(decide(screen) == .init(due: nil, next: nil))
    }

    @Test func anEndedTrialWithNothingSentSendsOnlyTheEndNotice() {
        let end = Self.now.addingTimeInterval(-3 * 24 * Self.hour)
        #expect(decide(.trialEnded(at: end)) == .init(due: .ended, next: nil))
    }

    /// Data wiped, Start pressed, and the server answered that the trial had already ended: this
    /// install never saw it running, so its end notice most likely went out on the day.
    @Test func anEndedTrialNeverSeenRunningSendsNothing() {
        let end = Self.now.addingTimeInterval(-3 * 24 * Self.hour)
        #expect(decide(.trialEnded(at: end), seenRunningUntil: .some(nil)) == .init(due: nil, next: nil))
    }

    /// Seen running only until an earlier end date, then extended elsewhere and ended unseen.
    @Test func anEndedTrialSeenRunningOnlyForAnotherEndSendsNothing() {
        let end = Self.now.addingTimeInterval(-60)
        let seen = end.addingTimeInterval(-2 * 24 * Self.hour)
        #expect(decide(.trialEnded(at: end), seenRunningUntil: .some(seen)) == .init(due: nil, next: nil))
    }

    @Test func anEndedTrialAfterTheDayBeforeNoticeSendsTheEndNotice() {
        let end = Self.now.addingTimeInterval(-60)
        #expect(decide(.trialEnded(at: end), sent: .init(dayBeforeForEnd: end)) == .init(due: .ended, next: nil))
    }

    @Test func anEndedTrialWithBothSentSendsNothing() {
        let end = Self.now.addingTimeInterval(-60)
        let sent = TrialNotice.Sent(dayBeforeForEnd: end, endedForEnd: end)
        #expect(decide(.trialEnded(at: end), sent: sent) == .init(due: nil, next: nil))
    }

    /// Support extended the trial: what was sent for the old end does not count for the new one.
    @Test func aNewEndDateSendsTheDayBeforeNoticeAgain() {
        let oldEnd = Self.now.addingTimeInterval(-2 * 24 * Self.hour)
        let (screen, end) = running(left: 12 * Self.hour)
        let sent = TrialNotice.Sent(dayBeforeForEnd: oldEnd, endedForEnd: oldEnd)
        #expect(decide(screen, sent: sent) == .init(due: .dayBefore, next: end))
    }

    @Test func aNewEndDateSendsTheEndNoticeAgain() {
        let oldEnd = Self.now.addingTimeInterval(-9 * 24 * Self.hour)
        let end = Self.now.addingTimeInterval(-60)
        let sent = TrialNotice.Sent(dayBeforeForEnd: oldEnd, endedForEnd: oldEnd)
        #expect(decide(.trialEnded(at: end), sent: sent) == .init(due: .ended, next: nil))
    }

    // MARK: The end date seen running

    @Test func aRunningTrialIsRememberedAsSeenRunning() {
        let (screen, end) = running(left: 3 * 24 * Self.hour)
        #expect(TrialNotice.seenRunningUntil(after: screen, previous: nil) == end)
    }

    @Test(arguments: [
        LicenceScreen.undetermined,
        .activateOnly,
        .offerTrial(isStarting: false),
        .trialEnded(at: now),
    ])
    func otherScreensKeepWhatWasSeen(_ screen: LicenceScreen) {
        #expect(TrialNotice.seenRunningUntil(after: screen, previous: Self.now) == Self.now)
    }

    @Test func aValidLicenceForgetsTheEndSeenRunning() {
        #expect(TrialNotice.seenRunningUntil(after: .licensed, previous: Self.now) == nil)
    }

    /// Bought during the trial, which then ended while licensed; months later the licence is
    /// removed to move it to another Mac. That end date is never sent the end notice.
    @Test func licensedWhileTheTrialEndedNothingIsEverSentForThatEnd() {
        let (runningScreen, end) = running(left: 2 * 24 * Self.hour)
        var seen = TrialNotice.seenRunningUntil(after: runningScreen, previous: nil)
        seen = TrialNotice.seenRunningUntil(after: .licensed, previous: seen)
        let ended = LicenceScreen.trialEnded(at: end)
        seen = TrialNotice.seenRunningUntil(after: ended, previous: seen)
        let later = end.addingTimeInterval(90 * 24 * Self.hour)
        let decision = TrialNotice.decision(screen: ended, now: later, sent: .init(), seenRunningUntil: seen)
        #expect(decision == .init(due: nil, next: nil))
    }

    /// Nobody with a stored licence, or one that may be stored, and nobody who has not started a
    /// trial, is ever sent either notice, whatever the dates and whatever was sent before.
    @Test(arguments: [
        LicenceScreen.licensed,
        .undetermined,
        .activateOnly,
        .offerTrial(isStarting: false),
        .offerTrial(isStarting: true),
    ])
    func noNoticeOutsideTheTrialScreens(_ screen: LicenceScreen) {
        let dates: [Date?] = [nil, Self.now, Self.now.addingTimeInterval(-60), Self.now.addingTimeInterval(60)]
        for dayBefore in dates {
            for ended in dates {
                let sent = TrialNotice.Sent(dayBeforeForEnd: dayBefore, endedForEnd: ended)
                for seen in dates {
                    #expect(decide(screen, sent: sent, seenRunningUntil: .some(seen)) == .init(due: nil, next: nil))
                }
            }
        }
    }
}

private extension LicenceScreen {
    var endForTests: Date? {
        switch self {
        case let .trialRunning(until, _): until
        case let .trialEnded(at): at
        case .licensed, .undetermined, .activateOnly, .offerTrial: nil
        }
    }
}
