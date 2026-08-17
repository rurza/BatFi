//
//  SystemChargeDrainTests.swift
//  BatFi
//
//  When macOS is draining the battery to the limit by itself, BatFi's mode is `.inhibit`
//  and the label has to say which of the two things `.inhibit` covers is happening. The
//  boundary is the whole decision: one point above the limit is a drain, exactly at it is a
//  hold, and getting that wrong leaves "Discharging to the limit" on screen for a battery
//  that has finished discharging.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SystemChargeDrainTests {
    @Test func aBatteryAboveTheLimitOnADrainingMechanismIsDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 61,
                limitInForce: 55,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// The drain has finished. The mode is still `.inhibit` and the mechanism still drains
    /// to the limit, so only the level tells the two states apart.
    @Test func aBatteryAtTheLimitIsHoldingNotDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 55,
                limitInForce: 55,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    @Test func aBatteryBelowTheLimitIsNotDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 54,
                limitInForce: 55,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// On every Mac whose firmware holds charge with an inhibit, sitting above the limit is
    /// BatFi pausing charging — nothing drains the battery on mains power.
    @Test func aMechanismThatDoesNotDrainNeverReportsADrain() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 61,
                limitInForce: 55,
                mechanismDrainsToLimitItself: false
            ) == false
        )
    }
}
