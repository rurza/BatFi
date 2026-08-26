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
                batteryPower: nil,
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
                batteryPower: nil,
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
                batteryPower: -7.0,
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
                batteryPower: nil,
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
                batteryPower: -7.0,
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
                batteryPower: -7.0,
                mechanismDrainsToLimitItself: false
            ) == false
        )
    }

    // MARK: - The plateau

    /// Measured 2026-08-26 12:57, ~3h after the charge itself finished: 100% against a 75%
    /// limit, `Amperage` 0, `FullyCharged` true, `NotChargingReason` bit 0 (`batteryFull`) and
    /// **not** bit 24 — so the firmware's own reason for not charging is that there is nothing
    /// left to charge, not that a limit is holding. macOS had taken the battery to full and had
    /// not yet given the limit back.
    ///
    /// The same episode as the climb, so the same state: a battery only reaches 100% above the
    /// user's limit because macOS put it there.
    @Test func aFullBatteryRestingAboveTheLimitIsStillTheTopUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: false,
                batteryPower: 0,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// Only at full. A battery resting *between* the limit and full was not put there by a
    /// calibration charge that ran to 100%, so there is no episode to attribute it to and
    /// nothing here should claim one.
    @Test func aBatteryRestingBelowFullIsNotTheTopUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 90,
                limitInForce: 75,
                isCharging: false,
                batteryPower: 0,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// A full battery being actively run down is the drain, not the plateau. This is the reading
    /// the plateau rule must not swallow — it is how the episode ends.
    @Test func aFullBatteryGivingCurrentUpIsTheDrainNotThePlateau() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: false,
                batteryPower: 7.4,
                mechanismDrainsToLimitItself: true
            ) == false
        )
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: false,
                batteryPower: 7.4,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// No SMC answer stays no answer, even at full. The plateau is claimed on evidence that the
    /// battery is resting, not on the level alone — which is the mistake this whole file is a
    /// record of.
    @Test func aFullBatteryWithNoSMCAnswerClaimsNothing() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100,
                limitInForce: 75,
                isCharging: false,
                batteryPower: nil,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// The property the two types exist to guarantee, swept rather than sampled — the failure
    /// this replaces was precisely one combination having the wrong owner.
    ///
    /// They are no longer complements, and that is the fix: each requires a *named* direction,
    /// so a reading that is neither (a full battery resting, or no SMC answer at all) is claimed
    /// by neither instead of falling to whichever one tested for an absence.
    @Test func eachStateRequiresItsOwnDirectionAndNeitherClaimsTheRest() {
        let powers: [Float?] = [nil, -46.2, -7.0, -0.04, 0, 0.04, 7.4, 46.2]
        for level in 70...100 {
            for isCharging in [true, false] {
                for power in powers {
                    let toppingUp = SystemChargeTopUp.isUnderway(
                        batteryLevel: level, limitInForce: 75,
                        isCharging: isCharging, batteryPower: power,
                        mechanismDrainsToLimitItself: true
                    )
                    let draining = SystemChargeDrain.isUnderway(
                        batteryLevel: level, limitInForce: 75,
                        isCharging: isCharging, batteryPower: power,
                        mechanismDrainsToLimitItself: true
                    )
                    let where_ = "level \(level), charging \(isCharging), power \(String(describing: power))"
                    #expect(!(toppingUp && draining), "both claimed \(where_)")

                    let flow = ChargeDirection.flow(isCharging: isCharging, batteryPower: power)
                    guard level > 75 else {
                        #expect(!toppingUp && !draining, "claimed at or below the limit: \(where_)")
                        continue
                    }
                    switch flow {
                    case .intoTheBattery:
                        #expect(toppingUp && !draining, "expected a top-up for \(where_)")
                    case .outOfTheBattery:
                        #expect(draining && !toppingUp, "expected a drain for \(where_)")
                    case .idle:
                        // Idle at full is the plateau; idle short of full belongs to neither.
                        if level >= 100 {
                            #expect(toppingUp && !draining, "expected the plateau for \(where_)")
                        } else {
                            #expect(!toppingUp && !draining, "expected neither for \(where_)")
                        }
                    case .unknown:
                        #expect(!toppingUp && !draining, "expected neither for \(where_)")
                    }
                }
            }
        }
    }
}
