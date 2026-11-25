//
//  ChargeDecisionRuleTests.swift
//  BatFi
//
//  The no-override arm of `ChargingManager.updateStatus` — charge, hold or discharge — moved
//  into a pure rule. It must change nothing: `legacyDecision` below is a line-for-line
//  transcription of the `if/else` chain as it stood in `ChargingManager`, and the rule has to
//  agree with it for every combination of inputs.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeDecisionRuleTests {
    /// Today's chain, transcribed. The `await`ed questions in the original are inputs here.
    private func legacyDecision(_ inputs: ChargeDecisionInputs) -> ChargeDecision {
        let currentBatteryLevel = inputs.batteryLevel
        let effectiveLimitInForce = inputs.limitInForce
        if currentBatteryLevel >= effectiveLimitInForce {
            if currentBatteryLevel > effectiveLimitInForce, inputs.allowDischarging, inputs.lidOpenOrSleepDisabled,
               !inputs.computerIsAsleep, !inputs.systemDischargesToLimitItself {
                return .discharge
            } else {
                return .inhibitAtLimit
            }
        } else if inputs.pausesChargingForSleep {
            return .inhibitForSleep
        } else if inputs.systemIsHoldingBelowLimit {
            return .inhibitBySystemHold
        } else if inputs.firmwareRangeIsHolding {
            return .inhibitByFirmwareRange
        } else {
            return .charge
        }
    }

    private func decide(
        level: Int,
        limit: Int,
        allowDischarging: Bool = false,
        lidOpen: Bool = false,
        asleep: Bool = false,
        drainsItself: Bool = false,
        pausesForSleep: Bool = false,
        systemHold: Bool = false,
        firmwareHold: Bool = false,
        sailing: SailingPhase? = nil
    ) -> ChargeDecision {
        ChargeDecisionRule.decide(ChargeDecisionInputs(
            batteryLevel: level,
            limitInForce: limit,
            allowDischarging: allowDischarging,
            lidOpenOrSleepDisabled: lidOpen,
            computerIsAsleep: asleep,
            systemDischargesToLimitItself: drainsItself,
            pausesChargingForSleep: pausesForSleep,
            systemIsHoldingBelowLimit: systemHold,
            firmwareRangeIsHolding: firmwareHold,
            sailingPhase: sailing
        ))
    }

    @Test func matchesTodaysBranchForEveryInput() {
        for level in [49, 50, 51, 79, 80, 81, 100] {
            for limit in [50, 80, 100] {
                for flags in 0..<(1 << 7) {
                    let bit = { (index: Int) in flags & (1 << index) != 0 }
                    let inputs = ChargeDecisionInputs(
                        batteryLevel: level,
                        limitInForce: limit,
                        allowDischarging: bit(0),
                        lidOpenOrSleepDisabled: bit(1),
                        computerIsAsleep: bit(2),
                        systemDischargesToLimitItself: bit(3),
                        pausesChargingForSleep: bit(4),
                        systemIsHoldingBelowLimit: bit(5),
                        firmwareRangeIsHolding: bit(6)
                    )
                    #expect(ChargeDecisionRule.decide(inputs) == legacyDecision(inputs), "\(inputs)")
                }
            }
        }
    }

    @Test func atTheLimitHolds() {
        #expect(decide(level: 80, limit: 80) == .inhibitAtLimit)
    }

    @Test func aboveTheLimitDischargesOnlyWhenAllowedAwakeLidOpenAndNotSystemDriven() {
        #expect(decide(level: 81, limit: 80, allowDischarging: true, lidOpen: true) == .discharge)
        #expect(decide(level: 81, limit: 80, allowDischarging: true, lidOpen: true, asleep: true) == .inhibitAtLimit)
        #expect(decide(level: 81, limit: 80, allowDischarging: true, lidOpen: true, drainsItself: true) == .inhibitAtLimit)
    }

    @Test func belowTheLimitPrecedenceIsSleepThenSystemHoldThenFirmwareThenCharge() {
        #expect(decide(level: 70, limit: 80, pausesForSleep: true, systemHold: true) == .inhibitForSleep)
        #expect(decide(level: 70, limit: 80, systemHold: true, firmwareHold: true) == .inhibitBySystemHold)
        #expect(decide(level: 70, limit: 80, firmwareHold: true) == .inhibitByFirmwareRange)
        #expect(decide(level: 79, limit: 80) == .charge)
    }

    // MARK: Sailing

    @Test func holdingBelowTheLimitIsASailingHold() {
        #expect(decide(level: 75, limit: 80, sailing: .holding) == .inhibitForSailing)
    }

    @Test func chargingPhaseChargesBelowTheLimit() {
        #expect(decide(level: 75, limit: 80, sailing: .charging) == .charge)
    }

    @Test func atOrAboveTheLimitTheOldArmsWin() {
        #expect(decide(level: 80, limit: 80, sailing: .holding) == .inhibitAtLimit)
        #expect(decide(level: 85, limit: 80, allowDischarging: true, lidOpen: true, sailing: .holding) == .discharge)
    }

    @Test func pauseOnSleepWinsOverSailing() {
        #expect(decide(level: 75, limit: 80, pausesForSleep: true, sailing: .holding) == .inhibitForSleep)
    }

    @Test func sailingHoldWinsOverTheSystemAndFirmwareHolds() {
        #expect(decide(level: 75, limit: 80, systemHold: true, firmwareHold: true, sailing: .holding) == .inhibitForSailing)
        #expect(decide(level: 75, limit: 80, systemHold: true, sailing: .charging) == .inhibitBySystemHold)
    }

    @Test func overrideArmHoldsOnlyWhenHolding() {
        #expect(ChargeDecisionRule.chargeOrHold(batteryLevel: 55, limitInForce: 60, sailingPhase: .holding) == .inhibitForSailing)
        #expect(ChargeDecisionRule.chargeOrHold(batteryLevel: 55, limitInForce: 60, sailingPhase: nil) == .charge)
        #expect(ChargeDecisionRule.chargeOrHold(batteryLevel: 60, limitInForce: 60, sailingPhase: nil) == .inhibitAtLimit)
        #expect(ChargeDecisionRule.chargeOrHold(batteryLevel: 55, limitInForce: 60, sailingPhase: .charging) == .charge)
        #expect(ChargeDecisionRule.chargeOrHold(batteryLevel: 65, limitInForce: 60, sailingPhase: .holding) == .inhibitAtLimit)
    }
}
