//
//  ChargeResumeNudgeTests.swift
//  BatFi
//
//  Measured on 26A5416b, 2026-08-19, against a live hold at 74% under a 75% limit:
//
//  - Re-writing the *same* limit does not re-open the charge session macOS closed. 75s of it,
//    plus PowerUIAgent's own periodic re-registrations, produced nothing.
//  - Raising the enforced limit by 3 points did, and it only had to be in force for about
//    **eight seconds** — BatFi's own revert-protection took it back to 75 after 8s and the
//    charger still re-armed. So the stimulus is the change, not the value that follows it.
//  - Current appeared ~25s after the change. IOKit reported it ~17s later still, which is why
//    nothing here may be paced off an IOKit reading.
//  - Restoring the target mid-charge does not cancel the session; the battery charged on and
//    stopped at 75%.
//
//  The delay before intervening is a product decision, not a measurement: nudging instantly
//  would write to a control the user can see in System Settings every time a heavy load dips
//  the charge below the limit for a moment.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeResumeNudgeTests {
    // MARK: - Where the nudge goes

    @Test func theNudgeGoesAFewPointsAboveTheLimitInForce() {
        #expect(ChargeResumeNudge.target(forLimitInForce: 75) == 78)
    }

    /// A limit near the top still gets a nudge, clamped rather than abandoned.
    @Test func theNudgeIsClampedToOneHundred() {
        #expect(ChargeResumeNudge.target(forLimitInForce: 98) == 100)
    }

    /// At 100 there is no room to raise, and an identical value is exactly what was measured
    /// not to re-arm anything. Nil rather than a write that cannot work.
    @Test func thereIsNoNudgeAvailableAtOneHundred() {
        #expect(ChargeResumeNudge.target(forLimitInForce: 100) == nil)
    }

    // MARK: - When the nudge fires

    private func monitor() -> ChargeResumeNudgeMonitor { ChargeResumeNudgeMonitor() }
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func aBriefHoldIsNotWorthAWrite() {
        var m = monitor()
        #expect(m.record(isHolding: true, at: start) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(30)) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(59)) == .none)
    }

    @Test func aHoldThatLastsIsNudged() {
        var m = monitor()
        _ = m.record(isHolding: true, at: start)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(60)) == .nudge)
    }

    /// One clean reading ends the run. The load lifting and the battery charging on its own is
    /// the common case, and it must not leave a half-elapsed clock behind to fire early on the
    /// next dip.
    @Test func aCleanReadingRestartsTheClock() {
        var m = monitor()
        _ = m.record(isHolding: true, at: start)
        #expect(m.record(isHolding: false, at: start.addingTimeInterval(59)) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(60)) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(119)) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(120)) == .nudge)
    }

    /// The cooldown exists because success cannot be observed quickly: ~25s for current to
    /// appear and ~17s more before IOKit admits it. A pass landing inside that window would
    /// otherwise read the hold as unchanged and nudge again on top of a working nudge.
    @Test func aNudgeIsNotRepeatedWhileTheFirstOneIsStillSettling() {
        var m = monitor()
        _ = m.record(isHolding: true, at: start)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(60)) == .nudge)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(70)) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(120)) == .none)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(239)) == .none)
    }

    /// A hold that survives the cooldown was not fixed by the first nudge, and is worth
    /// another. Bounded by the cooldown rather than by a retry count, because the fault has no
    /// natural end and a Mac left in it overnight should keep being offered a way out.
    @Test func aHoldThatSurvivesTheCooldownIsNudgedAgain() {
        var m = monitor()
        _ = m.record(isHolding: true, at: start)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(60)) == .nudge)
        #expect(m.record(isHolding: true, at: start.addingTimeInterval(240)) == .nudge)
    }
}
