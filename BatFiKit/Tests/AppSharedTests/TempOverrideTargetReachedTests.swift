//
//  TempOverrideTargetReachedTests.swift
//  BatFi
//
//  When an override the battery has reached is retired because the Mac's charge mechanism
//  cannot hold it — and the one override exempt from that: an inhibit held by freezing
//  Apple's charge limit.
//

import Foundation
import Shared
import Testing

@testable import AppShared

@Suite struct TempOverrideTargetReachedTests {
    private func retires(
        _ override: UserTempChargingMode,
        batteryLevel: Int,
        backend: ChargeBackend?
    ) -> Bool {
        TempOverrideTargetReached.retires(override, batteryLevel: batteryLevel, backend: backend)
    }

    // MARK: - The rule as it was

    /// A discharge to 55% that got there, on a backend that cannot pause: retired, so the
    /// battery is not discharged, charged back by the limit, and discharged again.
    @Test func aReachedTargetIsRetiredWhereChargingCannotBePaused() {
        #expect(retires(.init(limit: 55), batteryLevel: 55, backend: .systemChargeLimit))
        #expect(retires(.init(limit: 55), batteryLevel: 54, backend: .firmwareRange))
        #expect(retires(.init(limit: 55), batteryLevel: 55, backend: .unsupported))
    }

    @Test func aTargetNotYetReachedIsKept() {
        #expect(retires(.init(limit: 55), batteryLevel: 56, backend: .systemChargeLimit) == false)
    }

    /// The inhibit backends hold a target exactly.
    @Test func theInhibitBackendsKeepEveryOverride() {
        #expect(retires(.init(limit: 55), batteryLevel: 55, backend: .chte) == false)
        #expect(retires(.init(limit: 55), batteryLevel: 55, backend: .legacyCH0BC) == false)
    }

    /// "Run on Battery" keeps discharging until it is stopped or the charger comes out.
    @Test func runOnBatteryIsNeverRetired() {
        #expect(retires(.init(limit: 0), batteryLevel: 0, backend: .systemChargeLimit) == false)
    }

    /// "Charge to 100%" has its own completion rule.
    @Test func chargeToFullIsNeverRetiredHere() {
        #expect(retires(.init(limit: 100), batteryLevel: 100, backend: .systemChargeLimit) == false)
    }

    /// Unknown answers "can pause", the default `ChargingManager` has always taken.
    @Test func anUnknownBackendKeepsTheOverride() {
        #expect(retires(.init(limit: 55), batteryLevel: 55, backend: nil) == false)
    }

    // MARK: - The manual inhibit

    /// MPX-41. The inhibit is armed *at* the battery's level, so it has reached its target
    /// the moment it exists; retiring it is what made the "pause" last one pass.
    @Test func anInhibitHeldByTheFrozenLimitIsKept() {
        let inhibit = ManualInhibit.override(batteryLevel: 63, backend: .systemChargeLimit)
        #expect(retires(inhibit, batteryLevel: 63, backend: .systemChargeLimit) == false)
        #expect(retires(inhibit, batteryLevel: 62, backend: .systemChargeLimit) == false)
    }

    /// The exemption is the frozen limit, not the flag: where nothing can hold the level,
    /// an inhibit override is retired like any other.
    @Test func anInhibitIsStillRetiredWhereNothingCanHoldIt() {
        let inhibit = UserTempChargingMode(limit: 63, isInhibit: true)
        #expect(retires(inhibit, batteryLevel: 63, backend: .firmwareRange))
    }
}
