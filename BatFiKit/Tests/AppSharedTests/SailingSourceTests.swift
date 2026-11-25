//
//  SailingSourceTests.swift
//  BatFi
//
//  Whose sailing settings count this pass. The source follows the limit's: a temporary limit
//  (which beats a rule) sails by the main screen's switch and distance; an active rule sails
//  only by its own resume level; with neither, the main screen's settings apply.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SailingSourceTests {
    private func levels(
        mainSwitch: Bool = true,
        backendCanSail: Bool = true,
        target: Int,
        configuredLimit: Int = 80,
        configuredResume: Int? = 70,
        rule: AutomationTarget? = nil,
        override: UserTempChargingMode? = nil,
        holdingFullCharge: Bool = false
    ) -> SailingLevels? {
        SailingRange.levelsInPlay(
            enabled: mainSwitch,
            backendCanSail: backendCanSail,
            targetLimit: target,
            configuredLimit: configuredLimit,
            configuredResume: configuredResume,
            automation: rule,
            overrideInForce: override,
            holdingFullChargeUntilUnplugged: holdingFullCharge
        )
    }

    // MARK: - An active rule: only its own values count

    @Test func aSailingRuleSailsEvenWithTheMainSwitchOff() {
        #expect(levels(mainSwitch: false, target: 90, rule: AutomationTarget(limit: 90, resumeLevel: 50))
            == SailingLevels(limit: 90, resumeLevel: 50))
    }

    @Test func aRuleThatDoesNotSailHoldsAPlainLimitEvenWithTheMainSwitchOn() {
        #expect(levels(mainSwitch: true, target: 60, rule: AutomationTarget(limit: 60)) == nil)
    }

    @Test func nothingIsDerivedFromTheMainScreensDistanceForARule() {
        // 80–70 on the main screen would have made a 60% rule 50–60.
        #expect(levels(target: 60, rule: AutomationTarget(limit: 60, resumeLevel: 40))
            == SailingLevels(limit: 60, resumeLevel: 40))
    }

    @Test func aRuleLevelThatNoLongerFitsIsCorrectedNotInverted() {
        #expect(levels(target: 60, rule: AutomationTarget(limit: 60, resumeLevel: 70))
            == SailingLevels(limit: 60, resumeLevel: 55))
        #expect(levels(target: 80, rule: AutomationTarget(limit: 80, resumeLevel: 3))
            == SailingLevels(limit: 80, resumeLevel: 20))
    }

    @Test func aRuleBelowTwentyFiveDoesNotSail() {
        #expect(levels(target: 20, rule: AutomationTarget(limit: 20, resumeLevel: 20)) == nil)
    }

    @Test func aRuleIsJudgedAgainstTheLimitTheMacEnforces() {
        // A 60% rule where macOS holds 80% at the least: the rule's own resume level stays.
        #expect(levels(target: 80, rule: AutomationTarget(limit: 60, resumeLevel: 50))
            == SailingLevels(limit: 80, resumeLevel: 50))
    }

    @Test func aRuleDoesNotSailWhereTheBackendCannot() {
        #expect(levels(backendCanSail: false, target: 90, rule: AutomationTarget(limit: 90, resumeLevel: 50)) == nil)
    }

    @Test func chargeToFullAndItsHoldBeatASailingRule() {
        let rule = AutomationTarget(limit: 90, resumeLevel: 50)
        #expect(levels(target: 100, rule: rule, holdingFullCharge: true) == nil)
        #expect(levels(target: 100, rule: rule, override: UserTempChargingMode(limit: 100)) == nil)
    }

    @Test func aManualPauseBeatsASailingRule() {
        #expect(levels(target: 76, rule: AutomationTarget(limit: 90, resumeLevel: 50),
                       override: UserTempChargingMode(limit: 76, isInhibit: true)) == nil)
    }

    // MARK: - A temporary limit over a rule: the main screen's switch and distance, as before

    @Test func aTemporaryLimitOverASailingRuleFollowsTheMainSwitch() {
        let rule = AutomationTarget(limit: 90, resumeLevel: 50)
        #expect(levels(mainSwitch: false, target: 60, rule: rule, override: UserTempChargingMode(limit: 60)) == nil)
    }

    @Test func aTemporaryLimitOverARuleKeepsTheMainScreensDistance() {
        #expect(levels(mainSwitch: true, target: 60, rule: AutomationTarget(limit: 90),
                       override: UserTempChargingMode(limit: 60))
            == SailingLevels(limit: 60, resumeLevel: 50))
    }

    // MARK: - No rule: the main screen, unchanged

    @Test func withNoRuleTheMainScreenApplies() {
        #expect(levels(mainSwitch: true, target: 80) == SailingLevels(limit: 80, resumeLevel: 70))
        #expect(levels(mainSwitch: false, target: 80) == nil)
        #expect(levels(backendCanSail: false, target: 80) == nil)
    }

    // MARK: - Whether this pass's source has sailing on at all

    @Test func theSwitchInPlayFollowsTheSourceOfTheLimit() {
        let sailingRule = AutomationTarget(limit: 90, resumeLevel: 50)
        let plainRule = AutomationTarget(limit: 90)
        let temporary = UserTempChargingMode(limit: 60)
        #expect(SailingRange.switchIsOn(mainSwitch: false, automation: sailingRule, overrideInForce: nil))
        #expect(!SailingRange.switchIsOn(mainSwitch: true, automation: plainRule, overrideInForce: nil))
        #expect(SailingRange.switchIsOn(mainSwitch: true, automation: plainRule, overrideInForce: temporary))
        #expect(!SailingRange.switchIsOn(mainSwitch: false, automation: sailingRule, overrideInForce: temporary))
        #expect(SailingRange.switchIsOn(mainSwitch: true, automation: nil, overrideInForce: nil))
        #expect(!SailingRange.switchIsOn(mainSwitch: false, automation: nil, overrideInForce: nil))
    }

    // MARK: - A rule changing during a hold: the same path as a slider move

    @Test func aRuleTakingOverDuringAHoldKeepsThePhaseUnlessItsLevelsContradictIt() {
        var tracker = SailingPhaseTracker()
        // Holding at 75% under the main screen's 80–70.
        #expect(tracker.advance(chargerConnected: true, levels: levels(target: 80), overrideInForce: nil, batteryLevel: 75) == .holding)
        // A rule of 80–60 becomes active: still a hold, now down to 60.
        let quiet = levels(mainSwitch: false, target: 80, rule: AutomationTarget(limit: 80, resumeLevel: 60))
        #expect(tracker.advance(chargerConnected: true, levels: quiet, overrideInForce: nil, batteryLevel: 75) == .holding)
        // The rule is edited to 90–80: 75% is below its resume level, so charging starts.
        let raised = levels(mainSwitch: false, target: 90, rule: AutomationTarget(limit: 90, resumeLevel: 80))
        #expect(tracker.advance(chargerConnected: true, levels: raised, overrideInForce: nil, batteryLevel: 75) == .charging)
    }

    @Test func aRuleThatDoesNotSailEndsTheHold() {
        var tracker = SailingPhaseTracker()
        #expect(tracker.advance(chargerConnected: true, levels: levels(target: 80), overrideInForce: nil, batteryLevel: 75) == .holding)
        let plain = levels(target: 80, rule: AutomationTarget(limit: 80))
        #expect(tracker.advance(chargerConnected: true, levels: plain, overrideInForce: nil, batteryLevel: 75) == nil)
    }

    @Test func aSailingRuleEndingHandsBackToTheMainScreenWithThePhaseKept() {
        var tracker = SailingPhaseTracker()
        let rule = levels(mainSwitch: true, target: 90, rule: AutomationTarget(limit: 90, resumeLevel: 50))
        #expect(tracker.advance(chargerConnected: true, levels: rule, overrideInForce: nil, batteryLevel: 75) == .holding)
        // Back to the main screen's 80–70: 75% is inside it, the hold goes on.
        #expect(tracker.advance(chargerConnected: true, levels: levels(target: 80), overrideInForce: nil, batteryLevel: 75) == .holding)
    }
}
