//
//  TempOverrideDisconnectPolicyTests.swift
//  BatFi
//
//  Unit tests for the pure temp-override disconnect-removal policy.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct TempOverrideDisconnectPolicyTests {
    private typealias Policy = TempOverrideDisconnectPolicy
    private typealias Decision = TempOverrideDisconnectPolicy.Decision

    @Test func chargerConnectedAlwaysKeepsOverride() {
        #expect(Policy.decision(chargerConnected: true, batteryLevel: 50, overrideLimit: 80, secondsSinceDisconnect: 9999, overrideArmedBeforeDisconnect: true) == .keep)
        #expect(Policy.decision(chargerConnected: true, batteryLevel: 50, overrideLimit: 0, secondsSinceDisconnect: nil, overrideArmedBeforeDisconnect: true) == .keep)
    }

    /// The regression we are fixing: "Run on Battery" is a discharge override (battery sits
    /// above the override limit, e.g. limit 0). It must survive any length of charger
    /// disconnect — the charger being gone is precisely the state the user requested.
    @Test func dischargeOverrideIsNeverRemovedOnDisconnect() {
        // "Run on Battery" → limit 0, battery anywhere above 0.
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 0, secondsSinceDisconnect: 5, overrideArmedBeforeDisconnect: true) == .keep)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 0, secondsSinceDisconnect: 130, overrideArmedBeforeDisconnect: true) == .keep)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 1, overrideLimit: 0, secondsSinceDisconnect: 9999, overrideArmedBeforeDisconnect: true) == .keep)
        // Discharge-to-N override while still above N.
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 70, overrideLimit: 50, secondsSinceDisconnect: 9999, overrideArmedBeforeDisconnect: true) == .keep)
    }

    /// A charge override (battery below the limit) is the original "Charge to 100%" case —
    /// it stays subject to the prolonged-disconnect cleanup.
    @Test func chargeOverrideScheduledWhileInsideWindow() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 0, overrideArmedBeforeDisconnect: true) == .scheduleRemoval(after: 120))
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 90, overrideArmedBeforeDisconnect: true) == .scheduleRemoval(after: 30))
    }

    @Test func chargeOverrideRemovedPastWindow() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 120, overrideArmedBeforeDisconnect: true) == .removeNow)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 600, overrideArmedBeforeDisconnect: true) == .removeNow)
    }

    /// At-limit (hold / "Inhibit Charging") override: battery == limit. `c5754bb`
    /// deliberately included this case in the cleanup, so it stays removable on prolonged
    /// disconnect — only true discharge (battery > limit) is exempt.
    @Test func atLimitHoldOverrideStaysRemovable() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 80, overrideLimit: 80, secondsSinceDisconnect: 30, overrideArmedBeforeDisconnect: true) == .scheduleRemoval(after: 90))
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 80, overrideLimit: 80, secondsSinceDisconnect: 200, overrideArmedBeforeDisconnect: true) == .removeNow)
    }

    @Test func noRecordedDisconnectKeepsOverride() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: nil, overrideArmedBeforeDisconnect: true) == .keep)
    }

    /// The bug this parameter exists for, caught in a customer log on 2026-08-31.
    ///
    /// BatFi discharges a full battery back to the limit, which takes the adapter out of the
    /// circuit — so `ExternalConnected` reads false and the app records a disconnect at
    /// 10:30:08 with the charger still physically plugged in. Thirty-three minutes later the
    /// user clicks "Charge to 100%", and the status pass that follows the click reads
    /// `secondsSinceDisconnect` as 1991 and deletes the brand-new override:
    ///
    ///     11:03:19.912  Charger disconnected long enough, removing temp override
    ///     11:03:20.096  Updating charger connected status: true
    ///
    /// The window belongs to the *charger transition*, not to the click, so an override armed
    /// on battery is born past its own deadline. It is a standing request for the next
    /// connection, not something left over from the last one.
    @Test func overrideArmedAfterTheDisconnectIsNotStale() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 100, overrideLimit: 100, secondsSinceDisconnect: 1991, overrideArmedBeforeDisconnect: false) == .keep)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 206, overrideArmedBeforeDisconnect: false) == .keep)
    }

    /// And it is kept outright rather than having its clock restarted. Arming an override
    /// while on battery is how you ask for a top-up on the next connection; removing it two
    /// minutes later defeats that just as completely as removing it instantly, only later.
    @Test func overrideArmedAfterTheDisconnectIsNotMerelyRescheduled() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 0, overrideArmedBeforeDisconnect: false) == .keep)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 80, overrideLimit: 80, secondsSinceDisconnect: 30, overrideArmedBeforeDisconnect: false) == .keep)
    }

    /// The cleanup itself is unregressed: an override that predates the unplug is still
    /// dropped once the charger has been gone long enough.
    @Test func overrideArmedBeforeTheDisconnectStillGoes() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 1991, overrideArmedBeforeDisconnect: true) == .removeNow)
    }
}
