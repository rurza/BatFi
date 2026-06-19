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
        #expect(Policy.decision(chargerConnected: true, batteryLevel: 50, overrideLimit: 80, secondsSinceDisconnect: 9999) == .keep)
        #expect(Policy.decision(chargerConnected: true, batteryLevel: 50, overrideLimit: 0, secondsSinceDisconnect: nil) == .keep)
    }

    /// The regression we are fixing: "Run on Battery" is a discharge override (battery sits
    /// above the override limit, e.g. limit 0). It must survive any length of charger
    /// disconnect — the charger being gone is precisely the state the user requested.
    @Test func dischargeOverrideIsNeverRemovedOnDisconnect() {
        // "Run on Battery" → limit 0, battery anywhere above 0.
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 0, secondsSinceDisconnect: 5) == .keep)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 0, secondsSinceDisconnect: 130) == .keep)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 1, overrideLimit: 0, secondsSinceDisconnect: 9999) == .keep)
        // Discharge-to-N override while still above N.
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 70, overrideLimit: 50, secondsSinceDisconnect: 9999) == .keep)
    }

    /// A charge override (battery below the limit) is the original "Charge to 100%" case —
    /// it stays subject to the prolonged-disconnect cleanup.
    @Test func chargeOverrideScheduledWhileInsideWindow() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 0) == .scheduleRemoval(after: 120))
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 90) == .scheduleRemoval(after: 30))
    }

    @Test func chargeOverrideRemovedPastWindow() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 120) == .removeNow)
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: 600) == .removeNow)
    }

    /// At-limit (hold / "Inhibit Charging") override: battery == limit. `c5754bb`
    /// deliberately included this case in the cleanup, so it stays removable on prolonged
    /// disconnect — only true discharge (battery > limit) is exempt.
    @Test func atLimitHoldOverrideStaysRemovable() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 80, overrideLimit: 80, secondsSinceDisconnect: 30) == .scheduleRemoval(after: 90))
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 80, overrideLimit: 80, secondsSinceDisconnect: 200) == .removeNow)
    }

    @Test func noRecordedDisconnectKeepsOverride() {
        #expect(Policy.decision(chargerConnected: false, batteryLevel: 50, overrideLimit: 100, secondsSinceDisconnect: nil) == .keep)
    }
}
