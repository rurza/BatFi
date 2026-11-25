//
//  DelayAutomaticSleepTests.swift
//  BatFi
//
//  Unit tests for the pure rule that decides whether BatFi holds automatic sleep off while
//  the battery charges up to the limit.
//

import Foundation
import Testing

@testable import Shared

@Suite struct DelayAutomaticSleepTests {
    private func decide(
        enabled: Bool = true,
        batteryLevel: Int = 60,
        limit: Int = 80,
        chargerConnected: Bool = true,
        backend: ChargeBackend? = .chte,
        sailingIsHolding: Bool = false
    ) -> Bool {
        DelayAutomaticSleep.shouldPreventAutomaticSleep(
            enabled: enabled,
            batteryLevel: batteryLevel,
            limit: limit,
            chargerConnected: chargerConnected,
            backend: backend,
            sailingIsHolding: sailingIsHolding
        )
    }

    /// The ordinary case on a Mac BatFi can pause: below the limit on mains, so the Mac is
    /// kept awake until BatFi has had the chance to stop charging at the limit.
    @Test func holdsSleepOffBelowTheLimitWhereChargingCanBePaused() {
        #expect(decide(backend: .chte))
        #expect(decide(backend: .legacyCH0BC))
    }

    /// The bug. Under the firmware range and Apple's own charge limit the limit is enforced
    /// while the Mac sleeps, so keeping it awake protects nothing — and the system holds the
    /// battery a little below the limit, so "below the limit on mains" can stay true for
    /// hours and the Mac never auto-sleeps on AC.
    @Test func neverHoldsSleepOffWhereChargingCannotBePausedOnDemand() {
        for backend in ChargeBackend.allCases where !backend.canPauseChargingOnDemand {
            #expect(!decide(backend: backend), "\(backend.rawValue)")
        }
    }

    /// Fail open while the backend is unknown, matching the charging manager's other
    /// "can this Mac pause?" decisions: every Mac that works today can pause, and the first
    /// diagnostics call not having landed yet is not evidence against it.
    @Test func anUnknownBackendKeepsTheOrdinaryBehaviour() {
        #expect(decide(backend: nil))
    }

    @Test func theUsersSettingStillGovernsIt() {
        #expect(!decide(enabled: false))
    }

    @Test func atOrAboveTheLimitSleepIsAllowed() {
        #expect(!decide(batteryLevel: 80, limit: 80))
        #expect(!decide(batteryLevel: 95, limit: 80))
    }

    @Test func withoutAChargerSleepIsAllowed() {
        #expect(!decide(chargerConnected: false))
    }

    /// Below the limit while sailing holds is not "charging up to the limit": nothing is
    /// coming that the Mac has to stay awake for.
    @Test func noDelayWhileSailingHolds() {
        #expect(!decide(batteryLevel: 75, limit: 80, sailingIsHolding: true))
    }

    @Test func delayAsTodayWhileSailingCharges() {
        #expect(decide(batteryLevel: 65, limit: 80, sailingIsHolding: false))
    }
}
