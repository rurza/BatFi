//
//  SystemChargeHoldTests.swift
//  BatFi
//
//  Measured on 26A5416b, 2026-08-19: with a 60% limit in force the battery sat at 56% on
//  mains for two hours at exactly 0 mA, `CHNC` bit 24 set the whole time. macOS had drained
//  to the limit, closed the charge session, and a load heavier than the adapter then pulled
//  the battery below the limit — after which nothing re-opened the session.
//
//  The mode BatFi showed was `.charging` ("Charging to the limit"), because the decision
//  reads `batteryLevel < limitInForce` and assumes anything below the limit charges. On a
//  mechanism that owns the charging decision that assumption is false, and BatFi has no
//  write that can make it true. This rule is the missing input.
//
//  The boundary against `SystemChargeDrain` is the whole point: strictly below the limit is
//  this state, at or above it is that one, and the two must never both claim a battery.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SystemChargeHoldTests {
    // MARK: - The measured state

    /// The two hours at 56% against a 60% limit, 0 mA, firmware naming its own limit.
    @Test func aBatteryHeldBelowTheLimitByTheMechanismIsHeld() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 56,
                limitInForce: 60,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            )
        )
    }

    // MARK: - The healthy states this must never claim

    /// The ordinary case, and the one the old level comparison got right: below the limit
    /// with current going in is charging, whoever started it.
    @Test func aBatteryChargingBelowTheLimitIsNotHeld() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: true,
                batteryLevel: 56,
                limitInForce: 60,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    /// Sitting *at* the limit not charging is the mechanism working exactly as asked. It is
    /// already `.inhibit` without this rule, and claiming it here would relabel every
    /// healthy Mac that has reached its limit.
    @Test func aBatteryAtTheLimitIsNotHeldBelowIt() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 60,
                limitInForce: 60,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    /// Above the limit belongs to `SystemChargeDrain`, which reports the drain macOS runs to
    /// get down to it. Both rules claiming the same battery would put two contradictory
    /// sentences behind one mode.
    @Test func aBatteryAboveTheLimitIsNotHeldBelowIt() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 61,
                limitInForce: 60,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    /// Off the charger nothing is being held back — the battery is simply in use. Asked
    /// explicitly rather than inferred from the attribution, because a stale `CHNC` read
    /// must not be able to turn an unplugged Mac into a fault.
    @Test func aBatteryOffTheChargerIsNotHeld() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: false,
                isCharging: false,
                batteryLevel: 56,
                limitInForce: 60,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    // MARK: - Evidence, not assumption

    /// Nil is "not asked", never "nothing is holding" — the same reading `ChargeHoldDrift`
    /// gives it. Without the firmware naming the hold, a battery below the limit that is not
    /// charging is indistinguishable from one whose adapter cannot keep up with the load,
    /// and that state deserves a different answer.
    @Test func anUnaskedAttributionIsNotEvidenceOfAHold() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 56,
                limitInForce: 60,
                holdIsAttributed: nil,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    /// The firmware was asked and named nothing. Then charge is not being held by the limit,
    /// and the 0 mA has some other cause.
    @Test func anUnattributedHoldIsNotThisFault() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 56,
                limitInForce: 60,
                holdIsAttributed: false,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    /// On every Mac where BatFi holds charge with an inhibit of its own, below the limit
    /// means BatFi has already released it and the firmware charges. If it is not charging
    /// there, the limit has stopped working — which is `ChargeHoldDrift`'s question, with a
    /// remedy this state does not share.
    @Test func aMechanismBatFiDrivesItselfIsNotThisFault() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 56,
                limitInForce: 60,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: false
            ) == false
        )
    }

    // MARK: - The SMC outranks IOKit on a transition

    // Measured 2026-08-19 16:12:54, comparing BatFi's own menu against `ioreg` at the same
    // second: the SMC reported 46.2W flowing *into* the battery while `AppleSmartBattery` still
    // said `Amperage=0`, `IsCharging=false` and `CHNC` bit 24 set. IOKit did not catch up for
    // ~17s. So on the transition out of a hold, IOKit is stale and the SMC is right — and
    // without this the menu says "Charging paused by macOS" directly above its own graph showing
    // 46W going into the battery.

    @Test func chargeFlowingInEndsTheHoldEvenWhileIOKitStillSaysOtherwise() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 74,
                limitInForce: 75,
                holdIsAttributed: true,
                chargeIsFlowingIn: true,
                mechanismOwnsChargingDecision: true
            ) == false
        )
    }

    /// The SMC was asked and says nothing is going in. That is the hold, confirmed by the
    /// fresher of the two sources rather than merely unrefuted by the staler one.
    @Test func noChargeFlowingInConfirmsTheHold() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 74,
                limitInForce: 75,
                holdIsAttributed: true,
                chargeIsFlowingIn: false,
                mechanismOwnsChargingDecision: true
            )
        )
    }

    /// Nil is "not asked" here too. The SMC read is an XPC round trip, so callers that have not
    /// paid for one still get the IOKit answer rather than nothing.
    @Test func anUnaskedSMCLeavesTheIOKitAnswerStanding() {
        #expect(
            SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 74,
                limitInForce: 75,
                holdIsAttributed: true,
                chargeIsFlowingIn: nil,
                mechanismOwnsChargingDecision: true
            )
        )
    }
}
