//
//  OnBatterySettleTests.swift
//  BatFi
//
//  Unit tests for the wait before "Slow down on battery" believes the Mac is on its battery:
//  the start or end of BatFi's own force discharge can read as battery power for a moment
//  while the charger is in, and no app should be slowed down for that.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct OnBatterySettleTests {
    /// Goes on battery and hands back the wait that starts. The call stays out of `#require`,
    /// which cannot make a mutating one.
    private func goOnBattery(_ settle: inout OnBatterySettle) throws -> OnBatterySettle.Wait {
        let wait = settle.powerChanged(onBattery: true)
        return try #require(wait)
    }

    @Test func aFreshSettleIsNotOnBattery() {
        let settle = OnBatterySettle()
        #expect(!settle.isSettled)
    }

    @Test func goingOnBatteryStartsAWaitAndSlowsNothingYet() {
        var settle = OnBatterySettle()

        let wait = settle.powerChanged(onBattery: true)

        #expect(wait != nil)
        #expect(!settle.isSettled)
    }

    @Test func theWaitRunningOutSettlesItAndAsksForAPass() throws {
        var settle = OnBatterySettle()
        let wait = try goOnBattery(&settle)

        let settled = settle.waitRanOut(wait)

        #expect(settled)
        #expect(settle.isSettled)
        // Once only: the same timer ending twice asks for nothing more.
        let again = settle.waitRanOut(wait)
        #expect(!again)
        #expect(settle.isSettled)
    }

    /// Giving back on the charger never waits.
    @Test func theChargerEndsItAtOnce() throws {
        var settle = OnBatterySettle()
        let wait = try goOnBattery(&settle)
        _ = settle.waitRanOut(wait)

        let onCharger = settle.powerChanged(onBattery: false)

        #expect(onCharger == nil)
        #expect(!settle.isSettled)
    }

    /// The case it is for: a moment of "battery power" while BatFi's own discharge starts or
    /// ends, gone again before the wait runs out. Its timer then settles nothing.
    @Test func aBlipOnBatteryShorterThanTheWaitSlowsNothing() throws {
        var settle = OnBatterySettle()
        let blip = try goOnBattery(&settle)
        _ = settle.powerChanged(onBattery: false)

        let settled = settle.waitRanOut(blip)

        #expect(!settled)
        #expect(!settle.isSettled)
    }

    /// Only the latest stretch on battery counts: an earlier one's timer, still running
    /// across a blip on the charger, must not cut the new wait short.
    @Test func anEarlierStretchsTimerDoesNotSettleALaterOne() throws {
        var settle = OnBatterySettle()
        let first = try goOnBattery(&settle)
        _ = settle.powerChanged(onBattery: false)
        let second = try goOnBattery(&settle)

        let firstSettled = settle.waitRanOut(first)
        #expect(!firstSettled)
        #expect(!settle.isSettled)

        let secondSettled = settle.waitRanOut(second)
        #expect(secondSettled)
        #expect(settle.isSettled)
    }

    /// The power source reports again for things this does not read — time remaining,
    /// temperature — and each report must not start the wait over.
    @Test func stayingOnBatteryDoesNotRestartTheWait() throws {
        var settle = OnBatterySettle()
        let wait = try goOnBattery(&settle)

        let again = settle.powerChanged(onBattery: true)

        #expect(again == nil)
        let settled = settle.waitRanOut(wait)
        #expect(settled)
    }

    @Test func stayingOnTheChargerStartsNothing() {
        var settle = OnBatterySettle()
        #expect(settle.powerChanged(onBattery: false) == nil)
        #expect(!settle.isSettled)
    }

    @Test func theWaitIsTwoSecondsOnTheGivenClock() async {
        #expect(OnBatterySettle.duration == .seconds(2))
        let clock = ManualClock()
        let timer = Task { await OnBatterySettle.runOut(on: clock) }
        #expect(await eventually { clock.sleeperCount == 1 })

        clock.advance(by: .milliseconds(1999))
        #expect(clock.sleeperCount == 1)

        clock.advance(by: .milliseconds(1))
        let ranOut = await timer.value
        #expect(ranOut)
    }

    @Test func aWaitCancelledBeforeItRunsOutSettlesNothing() async {
        let clock = ManualClock()
        let timer = Task { await OnBatterySettle.runOut(on: clock) }
        #expect(await eventually { clock.sleeperCount == 1 })

        timer.cancel()

        let ranOut = await timer.value
        #expect(!ranOut)
    }
}
