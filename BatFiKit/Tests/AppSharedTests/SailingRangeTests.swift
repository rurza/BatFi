//
//  SailingRangeTests.swift
//  BatFi
//
//  The levels sailing works between: the resume level the slider shows, the one a temporary
//  limit derives from it, when sailing is in play at all, and how the two handles
//  push and stop each other.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SailingRangeTests {
    private func levels(
        enabled: Bool = true,
        target: Int = 80,
        configuredLimit: Int = 80,
        configuredResume: Int? = 70,
        override: UserTempChargingMode? = nil,
        holdingFullCharge: Bool = false
    ) -> SailingLevels? {
        SailingRange.levelsInPlay(
            enabled: enabled,
            targetLimit: target,
            configuredLimit: configuredLimit,
            configuredResume: configuredResume,
            overrideInForce: override,
            holdingFullChargeUntilUnplugged: holdingFullCharge
        )
    }

    @Test func firstTimeResumeIsTenBelowTheLimit() { #expect(SailingRange.resolvedResumeLevel(limit: 80, stored: nil) == 70) }

    @Test func resolvedResumeClampsAStaleStoredValue() {
        #expect(SailingRange.resolvedResumeLevel(limit: 80, stored: 80) == 75)
        #expect(SailingRange.resolvedResumeLevel(limit: 60, stored: 70) == 55)
        #expect(SailingRange.resolvedResumeLevel(limit: 80, stored: 10) == 20)
    }

    @Test func anotherLimitKeepsTheSameDistance() {
        #expect(SailingRange.resumeLevel(forLimit: 60, configuredLimit: 80, configuredResume: 70) == 50)
        #expect(SailingRange.resumeLevel(forLimit: 100, configuredLimit: 80, configuredResume: 70) == 90)
    }

    @Test func derivedResumeStopsAtTheFloor() {
        #expect(SailingRange.resumeLevel(forLimit: 50, configuredLimit: 80, configuredResume: 40) == 20)
    }

    @Test func noResumeWhereTheFloorLeavesNoGap() {
        #expect(SailingRange.resumeLevel(forLimit: 24, configuredLimit: 80, configuredResume: 70) == nil)
        #expect(SailingRange.resumeLevel(forLimit: 0, configuredLimit: 80, configuredResume: 70) == nil)
    }

    @Test func levelsAtTheConfiguredLimitWhenOn() {
        #expect(levels() == SailingLevels(limit: 80, resumeLevel: 70))
    }

    @Test func noLevelsWhenOff() { #expect(levels(enabled: false) == nil) }

    @Test func noLevelsForChargeToFullOrItsHold() {
        #expect(levels(override: UserTempChargingMode(limit: 100)) == nil)
        #expect(levels(holdingFullCharge: true) == nil)
    }

    @Test func noLevelsUnderAManualPause() {
        #expect(levels(override: UserTempChargingMode(limit: 76, isInhibit: true)) == nil)
    }

    @Test func temporaryLimitKeepsTheSameDistance() {
        #expect(levels(target: 60, configuredLimit: 80, configuredResume: 70, override: UserTempChargingMode(limit: 60))
            == SailingLevels(limit: 60, resumeLevel: 50))
    }

    @Test func draggingTheLimitPushesTheResumeAhead() {
        #expect(SailingRange.draggingLimit(to: 70, resume: 70) == SailingLevels(limit: 70, resumeLevel: 65))
        #expect(SailingRange.draggingLimit(to: 90, resume: 70) == SailingLevels(limit: 90, resumeLevel: 70))
    }

    @Test func draggingTheResumeStopsFiveShortAndAtTheFloor() {
        #expect(SailingRange.draggingResume(to: 80, limit: 80) == 75)
        #expect(SailingRange.draggingResume(to: 15, limit: 80) == 20)
    }

    @Test func trackStartsAtTwentyOnlyWhileOn() {
        #expect(SailingRange.trackLowerBound(sailingEnabled: true, lowestLimit: 50) == 20)
        #expect(SailingRange.trackLowerBound(sailingEnabled: false, lowestLimit: 50) == 50)
        #expect(SailingRange.trackLowerBound(sailingEnabled: false, lowestLimit: 80) == 80)
    }
}
