//
//  SailingPhaseTests.swift
//  BatFi
//
//  Whether sailing is charging up to the limit or holding while the battery drifts down to the
//  resume level, and when that phase is forgotten so the next pass starts fresh.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SailingPhaseTests {
    private let l7080 = SailingLevels(limit: 80, resumeLevel: 70)

    @Test(arguments: [(85, SailingPhase.holding), (80, .holding), (75, .holding), (70, .holding), (69, .charging)])
    func freshStartFollowsTheTable(level: Int, phase: SailingPhase) {
        #expect(SailingPhaseRule.next(after: nil, batteryLevel: level, levels: l7080) == phase)
    }

    @Test func chargingStopsOnlyAtTheLimit() {
        #expect(SailingPhaseRule.next(after: .charging, batteryLevel: 79, levels: l7080) == .charging)
        #expect(SailingPhaseRule.next(after: .charging, batteryLevel: 80, levels: l7080) == .holding)
    }

    @Test func holdingResumesOnlyBelowTheResumeLevel() {
        #expect(SailingPhaseRule.next(after: .holding, batteryLevel: 70, levels: l7080) == .holding)
        #expect(SailingPhaseRule.next(after: .holding, batteryLevel: 69, levels: l7080) == .charging)
    }

    @Test func levelChangesKeepThePhaseUnlessContradicted() {
        #expect(SailingPhaseRule.next(after: .charging, batteryLevel: 62, levels: SailingLevels(limit: 60, resumeLevel: 50)) == .holding)
        #expect(SailingPhaseRule.next(after: .holding, batteryLevel: 65, levels: SailingLevels(limit: 90, resumeLevel: 80)) == .charging)
        #expect(SailingPhaseRule.next(after: .charging, batteryLevel: 75, levels: SailingLevels(limit: 85, resumeLevel: 75)) == .charging)
    }

    @Test func trackerForgetsOnUnplug() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
        #expect(tracker.advance(chargerConnected: false, levels: l7080, overrideInForce: nil, batteryLevel: 75) == nil)
        #expect(tracker.phase == nil)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 69) == .charging)
    }

    @Test func trackerKeepsPhaseThroughBatFisOwnDischarge() {
        let connected = ChargerConnection.isConnected(reported: false, isDerived: true, appMode: .forceDischarge)
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
        #expect(tracker.advance(chargerConnected: connected, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
    }

    @Test func trackerForgetsWhenAnOverrideArmsOrEnds() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
        // Charge to 100% takes sailing out of play.
        #expect(tracker.advance(chargerConnected: true, levels: nil, overrideInForce: UserTempChargingMode(limit: 100), batteryLevel: 75) == nil)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
    }

    @Test func trackerKeepsChargingWhenATemporaryLimitArms() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 55) == .charging)
        // A temporary limit is a level change: the charging phase carries on up to the new limit.
        let override = UserTempChargingMode(limit: 60)
        let levels = SailingLevels(limit: 60, resumeLevel: 50)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: override, batteryLevel: 55) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: override, batteryLevel: 59) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: override, batteryLevel: 60) == .holding)
    }

    @Test func trackerKeepsHoldingWhenATemporaryLimitArms() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
        // Above the new limit; draining to it is not the tracker's business.
        let override = UserTempChargingMode(limit: 60)
        let levels = SailingLevels(limit: 60, resumeLevel: 50)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: override, batteryLevel: 75) == .holding)
    }

    @Test func trackerKeepsThePhaseWhenATemporaryLimitChanges() {
        var tracker = SailingPhaseTracker()
        let levels60 = SailingLevels(limit: 60, resumeLevel: 50)
        #expect(tracker.advance(chargerConnected: true, levels: levels60, overrideInForce: UserTempChargingMode(limit: 60), batteryLevel: 45) == .charging)
        // Kept, charging carries on to 65; a fresh start at 56 sits above 55.
        let levels65 = SailingLevels(limit: 65, resumeLevel: 55)
        #expect(tracker.advance(chargerConnected: true, levels: levels65, overrideInForce: UserTempChargingMode(limit: 65), batteryLevel: 56) == .charging)
    }

    @Test func trackerStartsFreshWhenATemporaryLimitEnds() {
        var tracker = SailingPhaseTracker()
        let override = UserTempChargingMode(limit: 85)
        let levels = SailingLevels(limit: 85, resumeLevel: 75)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: override, batteryLevel: 70) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: override, batteryLevel: 76) == .charging)
        // Kept, charging would carry on to 80; a fresh start at 76 sits above 70.
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 76) == .holding)
    }

    @Test func trackerStartsFreshAfterAManualPause() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 69) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .charging)
        let pause = UserTempChargingMode(limit: 75, isInhibit: true)
        #expect(tracker.advance(chargerConnected: true, levels: nil, overrideInForce: pause, batteryLevel: 75) == nil)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
    }

    @Test func trackerStartsFreshAfterChargeTo100() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 69) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: nil, overrideInForce: UserTempChargingMode(limit: 100), batteryLevel: 75) == nil)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
    }

    @Test func trackerForgetsWhenSailingIsOff() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 69) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: nil, overrideInForce: nil, batteryLevel: 75) == nil)
        #expect(tracker.phase == nil)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
    }

    @Test func forgetClearsThePhase() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 69) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .charging)
        tracker.forget()
        #expect(tracker.phase == nil)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
    }

    // MARK: - Fresh starts

    /// Where the firmware holds a band, a hold that starts afresh re-establishes the band at
    /// the current charge, so the tracker says which passes were fresh starts.
    @Test func trackerSaysWhenAPhaseStartedAfresh() {
        var tracker = SailingPhaseTracker()
        #expect(!tracker.startedAfresh)
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75)
        #expect(tracker.startedAfresh)
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 74)
        #expect(!tracker.startedAfresh)
    }

    @Test func anOverrideEndingIsAFreshStart() {
        let discharge = UserTempChargingMode(limit: 0)
        var tracker = SailingPhaseTracker()
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75)
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: discharge, batteryLevel: 74)
        #expect(!tracker.startedAfresh)
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 72)
        #expect(tracker.startedAfresh)
    }

    @Test func noPhaseIsNoFreshStart() {
        var tracker = SailingPhaseTracker()
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75)
        _ = tracker.advance(chargerConnected: false, levels: l7080, overrideInForce: nil, batteryLevel: 75)
        #expect(!tracker.startedAfresh)
        _ = tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75)
        tracker.forget()
        #expect(!tracker.startedAfresh)
    }

    @Test func chargeToLimitFirstThenSails() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .holding)
        tracker.chargeToLimitFirst()
        #expect(tracker.phase == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 75) == .charging)
        #expect(tracker.advance(chargerConnected: true, levels: l7080, overrideInForce: nil, batteryLevel: 80) == .holding)
    }
}
