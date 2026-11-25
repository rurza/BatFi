//
//  ChargeToFullCompletionTests.swift
//  BatFi
//
//  Unit tests for the pure "has the charge-to-full override met its goal?" rule.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeToFullCompletionTests {
    private typealias Completion = ChargeToFullCompletion

    /// The ordinary flow, unchanged: armed part-way up, the battery arrives at 100%, the
    /// override is done and BatFi goes back to managing the limit.
    @Test func overrideThatChargedTheBatteryToFullIsDone() {
        #expect(Completion.isReached(overrideLimit: 100, batteryLevel: 100, batteryLevelWhenArmed: 60))
        #expect(Completion.isReached(overrideLimit: 100, batteryLevel: 100, batteryLevelWhenArmed: 99))
    }

    /// The bug. A user watching a full battery drain back to the limit clicks
    /// "Charge to 100%" to stop it — and the rule read "the battery is at 100%" as
    /// "the override finished", so the next status pass deleted the click about 100 ms
    /// after it was made.
    ///
    /// `SystemChargeTopUp` has the measurement that makes this the common case rather than a
    /// one-frame race: `UISOC` stays pinned at 100 long after macOS starts draining, so the
    /// whole period in which this command is worth clicking reads as 100%.
    @Test func overrideArmedAgainstAnAlreadyFullBatteryIsNotDone() {
        #expect(!Completion.isReached(overrideLimit: 100, batteryLevel: 100, batteryLevelWhenArmed: 100))
    }

    /// Still climbing, so nothing to retire — with or without the guard.
    @Test func overrideStillChargingIsNotDone() {
        #expect(!Completion.isReached(overrideLimit: 100, batteryLevel: 99, batteryLevelWhenArmed: 60))
        #expect(!Completion.isReached(overrideLimit: 100, batteryLevel: 60, batteryLevelWhenArmed: 60))
    }

    /// This rule is the charge-to-*full* override's alone. A discharge or hold override at
    /// any other target is `TempOverrideDisconnectPolicy`'s business, and the discharge arm
    /// of `updateStatus`'s.
    @Test func overridesBelowFullAreNeverRetiredByThisRule() {
        #expect(!Completion.isReached(overrideLimit: 80, batteryLevel: 100, batteryLevelWhenArmed: 60))
        #expect(!Completion.isReached(overrideLimit: 0, batteryLevel: 100, batteryLevelWhenArmed: 100))
    }
}
