//
//  ChargeDirectionTests.swift
//  BatFi
//
//  The one rule `SystemChargeDrain` and `SystemChargeTopUp` both read, which is what makes
//  them exact complements above the limit. Every case here is a case where the two sources
//  disagree, because agreement was never the hard part.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeDirectionTests {
    /// The reading BatFi had no answer for: 100% against a 75% limit with 477 mA going in.
    @Test func iokitAloneIsEnoughToSayChargeIsGoingIn() {
        #expect(ChargeDirection.isFlowingIn(isCharging: true, chargeIsFlowingIn: nil))
    }

    @Test func iokitAloneIsEnoughToSayItIsNot() {
        #expect(ChargeDirection.isFlowingIn(isCharging: false, chargeIsFlowingIn: nil) == false)
    }

    /// The ~17s window measured on 26A5416b: the SMC reports current entering the battery
    /// while `AppleSmartBattery` still says 0 mA. Without this the label is wrong for the
    /// whole first third of a minute of every top-up.
    @Test func theSMCLeadsIOKitAndSettlesIt() {
        #expect(ChargeDirection.isFlowingIn(isCharging: false, chargeIsFlowingIn: true))
    }

    /// The asymmetry `SystemChargeHold` already applies: a `false` from the SMC cannot
    /// contradict IOKit's `true`, because a battery resting at 0 mA and one whose SMC read
    /// is merely stale look identical.
    @Test func theSMCCannotContradictIOKitInTheOtherDirection() {
        #expect(ChargeDirection.isFlowingIn(isCharging: true, chargeIsFlowingIn: false))
    }
}
