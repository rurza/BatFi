//
//  SystemChargeDrainTests.swift
//  BatFi
//
//  When macOS is draining the battery to the limit by itself, BatFi's mode is `.inhibit`
//  and the label has to say which of the things `.inhibit` covers is happening. Two
//  boundaries decide it, and both have been wrong: the level, where one point above the
//  limit is a drain and exactly at it is a hold; and the direction, where a battery above
//  the limit that is *taking* current is macOS topping it up rather than draining it.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SystemChargeDrainTests {
    @Test func aBatteryAboveTheLimitGivingCurrentUpIsDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 61,
                limitInForce: 55,
                isCharging: false,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// The regression, captured live on 26A5416b-class firmware 2026-08-26: 100% against a
    /// 75% limit in force, `IsCharging` true, `Amperage` +477, and BatFi reporting
    /// `systemIsDischargingToLimit: true` over it. The level test alone cannot tell Apple's
    /// documented calibration charge from the drain that follows it.
    @Test func aBatteryAboveTheLimitTakingCurrentIsNotDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: true,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// The SMC leads IOKit by ~17s, so for that window a top-up that has already begun
    /// still reads as `IsCharging` false. Trusting the level and IOKit alone puts
    /// "Discharging to the limit" over a battery the SMC can already see taking current.
    @Test func theSMCEndsADrainClaimBeforeIOKitDoes() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: false,
                chargeIsFlowingIn: true,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// The drain has finished. The mode is still `.inhibit` and the mechanism still drains
    /// to the limit, so only the level tells the two states apart.
    @Test func aBatteryAtTheLimitIsHoldingNotDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 55,
                limitInForce: 55,
                isCharging: false,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    @Test func aBatteryBelowTheLimitIsNotDraining() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 54,
                limitInForce: 55,
                isCharging: false,
                chargeIsFlowingIn: nil,
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
                isCharging: false,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: false
            ) == false
        )
    }
}
