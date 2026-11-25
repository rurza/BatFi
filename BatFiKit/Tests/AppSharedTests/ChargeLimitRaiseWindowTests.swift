//
//  ChargeLimitRaiseWindowTests.swift
//  BatFi
//
//  When a raised limit can still make a battery look held below it.
//
//  Two windows, both measured. powerd takes up to ~45 s to adopt a new limit, and after it
//  does, current starts ~25 s later and IOKit's `IsCharging` follows ~20 s after that. In
//  both, a battery that is about to charge reads as not charging, with the firmware's hold
//  attribution — cached for five minutes — still saying "held". Judged then, it is "Charging
//  paused by macOS", which is false, and was announced.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeLimitRaiseWindowTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func aSteadyAdoptedLimitIsNotInAWindow() {
        var window = ChargeLimitRaiseWindow()
        #expect(window.record(enforced: 80, applied: 80, now: at(0)).suppressesHold == false)
        #expect(window.record(enforced: 80, applied: 80, now: at(30)).suppressesHold == false)
    }

    /// powerd still on the old value under a raised one.
    @Test func aRaiseNotYetAdoptedSuppressesTheHold() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 77, applied: 77, now: at(0))
        #expect(window.record(enforced: 77, applied: 80, now: at(5)).suppressesHold)
    }

    /// The post-adoption lag: the hold stays suppressed for the settle interval after powerd
    /// is seen enforcing the raised value, and not a moment longer.
    @Test func anAdoptedRaiseSuppressesTheHoldUntilChargingCanHaveStarted() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 77, applied: 80, now: at(0))
        #expect(window.record(enforced: 80, applied: 80, now: at(40)).suppressesHold)
        #expect(window.record(enforced: 80, applied: 80, now: at(40 + ChargeLimitRaiseWindow.settleInterval - 1)).suppressesHold)
        #expect(window.record(enforced: 80, applied: 80, now: at(40 + ChargeLimitRaiseWindow.settleInterval)).suppressesHold == false)
    }

    /// The settle interval has to cover the measured lag — ~25 s to current, ~20 s more to
    /// IOKit — with room to spare.
    @Test func theSettleIntervalCoversTheMeasuredLag() {
        #expect(ChargeLimitRaiseWindow.settleInterval >= 90)
    }

    /// A lowered limit cannot make a battery look held below it; no window.
    @Test func aLoweredLimitOpensNoWindow() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 80, applied: 80, now: at(0))
        #expect(window.record(enforced: 75, applied: 75, now: at(40)).suppressesHold == false)
    }

    /// No policy (on battery, or unreadable) between two readings does not hide a raise.
    @Test func aMissingPolicyBetweenReadingsDoesNotHideARaise() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 77, applied: 80, now: at(0))
        _ = window.record(enforced: nil, applied: 80, now: at(10))
        #expect(window.record(enforced: 80, applied: 80, now: at(20)).suppressesHold)
    }

    // MARK: - The cached attribution

    /// The firmware's attribution is cached for five minutes, and one read before or during
    /// adoption says "held" by the old limit. Any change in the enforced value, either way,
    /// makes it stale.
    @Test func aChangeInTheEnforcedLimitInvalidatesTheAttribution() {
        var window = ChargeLimitRaiseWindow()
        #expect(window.record(enforced: 77, applied: 80, now: at(0)).enforcedLimitChanged == false)
        #expect(window.record(enforced: 77, applied: 80, now: at(5)).enforcedLimitChanged == false)
        #expect(window.record(enforced: 80, applied: 80, now: at(40)).enforcedLimitChanged)
        #expect(window.record(enforced: 80, applied: 80, now: at(45)).enforcedLimitChanged == false)
        #expect(window.record(enforced: 75, applied: 75, now: at(60)).enforcedLimitChanged)
    }

    /// So does a change in the limit BatFi applied, before powerd has moved at all.
    @Test func aChangeInTheAppliedLimitInvalidatesTheAttribution() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 77, applied: 77, now: at(0))
        #expect(window.record(enforced: 77, applied: 80, now: at(1)).appliedLimitChanged)
        #expect(window.record(enforced: 77, applied: 80, now: at(2)).appliedLimitChanged == false)
    }

    /// A failed apply leaves the pass with the limit it asked for — 70 on a Mac whose floor is
    /// 80 — and recorded, the next apply that succeeded read as a change from 70 to 80.
    @Test func aFailedApplyIsNotRecordedAsApplied() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 80, applied: 80, now: at(0))
        let failed = window.record(enforced: 80, applied: 70, appliedWasConfirmed: false, now: at(1))
        #expect(failed.appliedLimitChanged == false)
        #expect(window.lastAppliedLimit == 80)
        #expect(window.record(enforced: 80, applied: 80, now: at(2)).appliedLimitChanged == false)
    }

    @Test func theLastAppliedLimitIsTheLastOneRecorded() {
        var window = ChargeLimitRaiseWindow()
        #expect(window.lastAppliedLimit == nil)
        _ = window.record(enforced: nil, applied: 85, now: at(0))
        #expect(window.lastAppliedLimit == 85)
    }
}
