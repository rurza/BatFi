//
//  SystemChargeTopUpTests.swift
//  BatFi
//
//  Apple's documented calibration charge, seen from inside BatFi. The state BatFi had no
//  representation for, which is why it was being reported as its own opposite: measured on
//  this machine 2026-08-26 at 100% against a 75% limit in force, `IsCharging` true,
//  `Amperage` +477, 7.0 W entering the battery — and the menu read "Discharging to the
//  limit" over it.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SystemChargeTopUpTests {
    /// The captured reading, exactly as it came off the machine.
    @Test func aBatteryAboveTheLimitTakingCurrentIsToppingUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: true,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// The top-up in progress, before it reaches full.
    @Test func aBatteryClimbingPastTheLimitIsToppingUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 82,
                limitInForce: 75,
                isCharging: true,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// The first seconds of a top-up, where IOKit has not caught up yet. Without the SMC
    /// this reads as a drain — the very bug — for as long as the lag lasts.
    @Test func theSMCCatchesTheStartOfATopUpBeforeIOKitDoes() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 76,
                limitInForce: 75,
                isCharging: false,
                chargeIsFlowingIn: true,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// macOS draining back down to the limit after a top-up. Above the limit and on the
    /// charger, exactly like the top-up, and the direction is the only thing that separates
    /// them.
    @Test func aBatteryAboveTheLimitGivingCurrentUpIsNotToppingUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: false,
                chargeIsFlowingIn: nil,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// Strictly above the limit, matching `SystemChargeDrain`. An ordinary charge that has
    /// just reached the limit reads as charging at exactly the limit for as long as IOKit
    /// takes to notice it stopped — and calling that a top-up past the limit would relabel
    /// every healthy Mac at the moment it finishes charging.
    @Test func aBatteryAtTheLimitIsNotToppingUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 75,
                limitInForce: 75,
                isCharging: true,
                chargeIsFlowingIn: true,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// On every Mac whose firmware holds charge with an inhibit of BatFi's own, charging
    /// past the limit is not macOS overriding anything — it is `ChargeHoldDrift`'s fault to
    /// report, and Apple's charge limit is not the mechanism in force.
    @Test func aMechanismBatFiDrivesItselfNeverReportsATopUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: true,
                chargeIsFlowingIn: true,
                mechanismDrainsToLimitItself: false
            ) == false
        )
    }

    /// The property the two types exist to guarantee. Sweeping the whole space rather than
    /// naming cases, because the failure this fixes was precisely one of these combinations
    /// having no owner.
    @Test func theTopUpAndTheDrainNeverBothClaimAReading() {
        for level in 70...100 {
            for isCharging in [true, false] {
                for flowing in [true, false, nil] {
                    let toppingUp = SystemChargeTopUp.isUnderway(
                        batteryLevel: level,
                        limitInForce: 75,
                        isCharging: isCharging,
                        chargeIsFlowingIn: flowing,
                        mechanismDrainsToLimitItself: true
                    )
                    let draining = SystemChargeDrain.isUnderway(
                        batteryLevel: level,
                        limitInForce: 75,
                        isCharging: isCharging,
                        chargeIsFlowingIn: flowing,
                        mechanismDrainsToLimitItself: true
                    )
                    #expect(!(toppingUp && draining), "both claimed level \(level), charging \(isCharging), flowing \(String(describing: flowing))")
                    // And above the limit exactly one of them owns the reading, so no state
                    // above the limit can fall through to a label about a hold.
                    if level > 75 {
                        #expect(toppingUp != draining, "neither claimed level \(level), charging \(isCharging), flowing \(String(describing: flowing))")
                    }
                }
            }
        }
    }
}
