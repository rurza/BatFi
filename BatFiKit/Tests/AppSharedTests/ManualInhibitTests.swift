//
//  ManualInhibitTests.swift
//  BatFi
//
//  "Inhibit Charging" — the menu item and its hotkey — on every backend. Where BatFi has an
//  inhibit of its own it arms an override at the battery's level and the inhibit holds it;
//  under Apple's charge limit there is no inhibit, so the same override is held by freezing
//  Apple's limit at that level instead.
//

import Foundation
import Shared
import Testing

@testable import AppShared

@Suite struct ManualInhibitTests {
    // MARK: - Where it is offered

    @Test func availableOnTheInhibitBackends() {
        #expect(ManualInhibit.isAvailable(on: .chte))
        #expect(ManualInhibit.isAvailable(on: .legacyCH0BC))
    }

    /// The customer's case (MPX-41): the command disappeared on macOS 27 firmware and is back,
    /// held by Apple's own limit.
    @Test func availableUnderTheSystemChargeLimit() {
        #expect(ManualInhibit.isAvailable(on: .systemChargeLimit))
    }

    /// A band at the current level lets the battery fall five points and charges it back up,
    /// so there is still nothing here that holds charge where it is.
    @Test func notAvailableUnderTheFirmwareRange() {
        #expect(ManualInhibit.isAvailable(on: .firmwareRange) == false)
    }

    @Test func notAvailableWhereNothingIsSupported() {
        #expect(ManualInhibit.isAvailable(on: .unsupported) == false)
    }

    /// Fail-open, as the menu and the charging manager always have been.
    @Test func availableWhileTheBackendIsUnknown() {
        #expect(ManualInhibit.isAvailable(on: nil))
    }

    @Test func agreesWithHoldingChargeAtTheCurrentLevelForEveryBackend() {
        for backend in ChargeBackend.allCases {
            #expect(ManualInhibit.isAvailable(on: backend) == backend.canHoldChargeAtCurrentLevel)
        }
    }

    // MARK: - The override it arms

    /// Unchanged on the inhibit backends: the battery's level exactly, whatever it is.
    @Test func theInhibitBackendsArmTheExactLevel() {
        #expect(ManualInhibit.override(batteryLevel: 63, backend: .chte).limit == 63)
        #expect(ManualInhibit.override(batteryLevel: 87, backend: .chte).limit == 87)
        #expect(ManualInhibit.override(batteryLevel: 87, backend: .legacyCH0BC).limit == 87)
    }

    /// Below 80 Apple's limit takes any value, so the level is held as it is.
    @Test func theSystemChargeLimitHoldsALevelBelow80AsItIs() {
        #expect(ManualInhibit.override(batteryLevel: 63, backend: .systemChargeLimit).limit == 63)
        #expect(ManualInhibit.override(batteryLevel: 79, backend: .systemChargeLimit).limit == 79)
    }

    /// From 80 up the value goes through `setMCLLimit:`, which rounds 87 *up* to 90 — and a
    /// pause that charges three more percent is not a pause. Rounded down instead, the way
    /// the hot-battery hold rounds, so macOS drains a point or two rather than charging on.
    @Test func theSystemChargeLimitRoundsALevelFrom80DownToItsStep() {
        #expect(ManualInhibit.override(batteryLevel: 80, backend: .systemChargeLimit).limit == 80)
        #expect(ManualInhibit.override(batteryLevel: 87, backend: .systemChargeLimit).limit == 85)
        #expect(ManualInhibit.override(batteryLevel: 99, backend: .systemChargeLimit).limit == 95)
        #expect(ManualInhibit.override(batteryLevel: 100, backend: .systemChargeLimit).limit == 100)
    }

    /// An unknown backend is not guessed at: the level, as the inhibit backends arm it.
    @Test func anUnknownBackendArmsTheExactLevel() {
        #expect(ManualInhibit.override(batteryLevel: 87, backend: nil).limit == 87)
    }

    @Test func theOverrideSaysItIsAnInhibit() {
        for backend in ChargeBackend.allCases {
            #expect(ManualInhibit.override(batteryLevel: 63, backend: backend).isInhibit)
        }
    }

    /// Armed before the backend is known, the level is not rounded — so it must never later
    /// become a frozen inhibit. Resolved to Apple's limit, 87 would be rounded *up* to 90 and
    /// exempt from retirement: the battery charging three points under a "pause". As a plain
    /// override it is retired the way it always was, which is the safe failure.
    @Test func anOverrideArmedOnAnUnknownBackendIsNeverAFrozenInhibit() {
        let override = ManualInhibit.override(batteryLevel: 87, backend: nil)
        #expect(override.isInhibit == false)
        #expect(ManualInhibit.isHeldByFrozenLimit(override, backend: .systemChargeLimit) == false)
    }

    /// Every other route to an override — Charge to 100%, Run on Battery, the Shortcuts
    /// intent — arms a plain one.
    @Test func aPlainOverrideIsNotAnInhibit() {
        #expect(UserTempChargingMode(limit: 63).isInhibit == false)
    }

    /// Same limit, different request: an inhibit replacing a plain override at the same
    /// value has to reach the charging manager as a change.
    @Test func anInhibitIsNotEqualToAPlainOverrideAtTheSameLimit() {
        #expect(UserTempChargingMode(limit: 63, isInhibit: true) != UserTempChargingMode(limit: 63))
    }

    // MARK: - Whether the override in force is held by freezing Apple's limit

    @Test func anInhibitUnderTheSystemChargeLimitIsHeldByTheFrozenLimit() {
        #expect(ManualInhibit.isHeldByFrozenLimit(UserTempChargingMode(limit: 63, isInhibit: true), backend: .systemChargeLimit))
    }

    /// The inhibit backends hold it with their inhibit, exactly as before.
    @Test func anInhibitOnTheInhibitBackendsIsNotAFrozenLimit() {
        #expect(ManualInhibit.isHeldByFrozenLimit(UserTempChargingMode(limit: 63, isInhibit: true), backend: .chte) == false)
        #expect(ManualInhibit.isHeldByFrozenLimit(UserTempChargingMode(limit: 63, isInhibit: true), backend: .legacyCH0BC) == false)
    }

    @Test func aPlainOverrideIsNeverAFrozenLimit() {
        #expect(ManualInhibit.isHeldByFrozenLimit(UserTempChargingMode(limit: 63), backend: .systemChargeLimit) == false)
    }

    @Test func noOverrideIsNoFrozenLimit() {
        #expect(ManualInhibit.isHeldByFrozenLimit(nil, backend: .systemChargeLimit) == false)
    }

    @Test func anUnknownBackendHoldsNothingByFreezing() {
        #expect(ManualInhibit.isHeldByFrozenLimit(UserTempChargingMode(limit: 63, isInhibit: true), backend: nil) == false)
    }

    @Test func noBackendThatCannotHoldAtTheCurrentLevelFreezes() {
        for backend in [ChargeBackend.firmwareRange, .unsupported] {
            #expect(ManualInhibit.isHeldByFrozenLimit(UserTempChargingMode(limit: 63, isInhibit: true), backend: backend) == false)
        }
    }

    // MARK: - Alongside a hot-battery hold

    /// Both are limits on this backend, and the lower one wins — whichever it is.
    @Test func theLowerOfAHotBatteryHoldAndAnInhibitIsRequested() {
        #expect(HotBatteryHold.requestedLimit(frozenAt: 60, otherwise: 63) == 60)
        #expect(HotBatteryHold.requestedLimit(frozenAt: 70, otherwise: 63) == 63)
    }
}
