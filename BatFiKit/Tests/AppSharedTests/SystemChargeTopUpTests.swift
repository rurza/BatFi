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

    /// macOS draining back down to the limit after a top-up. Below full, where the reading
    /// governs, the direction is the only thing separating this from the climb. At full the
    /// plateau owns it either way — see `atFullEverySMCReadingGivesTheSameAnswer`.
    @Test func aBatteryBelowFullGivingCurrentUpIsNotToppingUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 99,
                limitInForce: 75,
                isCharging: false,
                batteryPower: 7.4,
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

    // MARK: - The plateau, and why it does not read the SMC

    /// Measured 2026-08-26 12:57, ~3h after the charge itself finished, and still there at
    /// 14:01: 100% against a 75% limit, `Amperage` 0, `FullyCharged` true,
    /// `NotChargingReason` bit 0 (`batteryFull`) and **not** bit 24 — the firmware's own
    /// reason for not charging is that there is nothing left to charge. macOS had taken the
    /// battery to full and had not given the limit back for hours.
    @Test func aFullBatteryRestingAboveTheLimitIsTheTopUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 100, limitInForce: 75,
                isCharging: false, batteryPower: 0,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// The stability requirement, and the reason the level decides this and the SMC does not.
    ///
    /// Measured 2026-08-26 13:59–14:03: at 100% and resting, `batteryPower` crossed a 0.1 W
    /// threshold nine times in four minutes — 90 successful SMC reads in the same window, so
    /// the helper was answering and the *value* was moving. A full battery on the charger sits
    /// near zero and jitters, and it briefly supplements the adapter whenever a load burst
    /// outruns it. Each crossing flipped the label and fired a "New mode" notification, so the
    /// user was flooded.
    ///
    /// At full there is nothing an instantaneous reading can add: a battery at 100% above the
    /// user's limit is macOS's doing whichever way a few tenths of a watt happen to be moving.
    /// So every sign is the same answer here, and the state cannot flap.
    @Test func atFullEverySMCReadingGivesTheSameAnswer() {
        let powers: [Float?] = [nil, -46.2, -0.09, 0, 0.09, 0.4, 7.4, 46.2]
        for power in powers {
            for isCharging in [true, false] {
                #expect(
                    SystemChargeTopUp.isUnderway(
                        batteryLevel: 100, limitInForce: 75,
                        isCharging: isCharging, batteryPower: power,
                        mechanismDrainsToLimitItself: true
                    ),
                    "flapped at power \(String(describing: power)), charging \(isCharging)"
                )
                #expect(
                    SystemChargeDrain.isUnderway(
                        batteryLevel: 100, limitInForce: 75,
                        isCharging: isCharging, batteryPower: power,
                        mechanismDrainsToLimitItself: true
                    ) == false,
                    "claimed a drain at full: power \(String(describing: power)), charging \(isCharging)"
                )
            }
        }
    }

    /// The cost of the rule above, stated so it is a decision rather than an oversight: a drain
    /// that has begun but not yet moved the level off 100 is reported as the plateau. It is the
    /// same episode either way, and the drain gets its own label the moment the battery reads
    /// 99. Trading a late label for a stable one, because the unstable one flooded the user.
    @Test func aDrainIsNotReportedUntilTheLevelLeavesFull() {
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 100, limitInForce: 75,
                isCharging: false, batteryPower: 7.4,
                mechanismDrainsToLimitItself: true
            ) == false
        )
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 99, limitInForce: 75,
                isCharging: false, batteryPower: 7.4,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// Only at full. A battery resting *between* the limit and full was not put there by a
    /// calibration charge that ran to 100%, so there is no episode to attribute a rest to.
    @Test func aBatteryRestingBelowFullIsNotTheTopUp() {
        #expect(
            SystemChargeTopUp.isUnderway(
                batteryLevel: 90, limitInForce: 75,
                isCharging: false, batteryPower: 0,
                mechanismDrainsToLimitItself: true
            ) == false
        )
    }

    /// Below full the reading still governs, and the threshold has to clear the same jitter.
    /// A drain macOS performs on purpose runs at several watts; a few tenths is a resting
    /// battery trading with the adapter.
    @Test func belowFullOnlyARealOutwardFlowIsADrain() {
        for noise in [Float(0.4), 0.9, -0.9] {
            #expect(
                SystemChargeDrain.isUnderway(
                    batteryLevel: 90, limitInForce: 75,
                    isCharging: false, batteryPower: noise,
                    mechanismDrainsToLimitItself: true
                ) == false,
                "called \(noise) W a drain"
            )
        }
        #expect(
            SystemChargeDrain.isUnderway(
                batteryLevel: 90, limitInForce: 75,
                isCharging: false, batteryPower: 6.0,
                mechanismDrainsToLimitItself: true
            )
        )
    }

    /// The property the two types exist to guarantee, swept rather than sampled — the failure
    /// this replaces was precisely one combination having the wrong owner.
    ///
    /// They are no longer complements, and that is the fix: each requires a *named* direction,
    /// so a reading that is neither (a full battery resting, or no SMC answer at all) is claimed
    /// by neither instead of falling to whichever one tested for an absence.
    @Test func eachStateRequiresItsOwnDirectionAndNeitherClaimsTheRest() {
        let powers: [Float?] = [nil, -46.2, -7.0, -0.4, 0, 0.4, 7.4, 46.2]
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
                    guard level < 100 else {
                        // At full the level decides and the reading is not consulted, so no
                        // sign of `batteryPower` can move this.
                        #expect(toppingUp && !draining, "expected the plateau for \(where_)")
                        continue
                    }
                    switch flow {
                    case .intoTheBattery:
                        #expect(toppingUp && !draining, "expected a top-up for \(where_)")
                    case .outOfTheBattery:
                        #expect(draining && !toppingUp, "expected a drain for \(where_)")
                    case .idle, .unknown:
                        #expect(!toppingUp && !draining, "expected neither for \(where_)")
                    }
                }
            }
        }
    }
}
