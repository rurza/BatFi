//
//  AutomationRuleSailingTests.swift
//  BatFi
//
//  A rule carries its own second charge level: saved rules from before it decode without one,
//  and a stored level that no longer fits the rule's limit is corrected when read, never trusted.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct AutomationRuleSailingTests {
    // MARK: - Storage

    @Test func aRuleSavedBeforeSailingDecodesWithoutAResumeLevel() throws {
        let json = """
        [{"id":"6F1D3C2A-1B2C-4D5E-8F90-1234567890AB","name":"Work","isEnabled":true,"limit":60}]
        """
        let rules = try JSONDecoder().decode([AutomationRule].self, from: Data(json.utf8))
        #expect(rules.count == 1)
        #expect(rules[0].limit == 60)
        #expect(rules[0].resumeLevel == nil)
        #expect(rules[0].sailingLevels == nil)
    }

    @Test func aRuleWithoutAResumeLevelIsSavedWithoutTheKey() throws {
        // What an older build reads back is then byte-for-byte the shape it always wrote.
        let data = try JSONEncoder().encode(AutomationRule(name: "Home", limit: 80))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["resumeLevel"] == nil)
    }

    @Test func aResumeLevelRoundTrips() throws {
        let rule = AutomationRule(name: "Work", limit: 90, resumeLevel: 50)
        let decoded = try JSONDecoder().decode(AutomationRule.self, from: JSONEncoder().encode(rule))
        #expect(decoded == rule)
        #expect(decoded.resumeLevel == 50)
    }

    @Test func aKeyFromALaterBuildIsIgnored() throws {
        let json = """
        {"id":"6F1D3C2A-1B2C-4D5E-8F90-1234567890AB","name":"Work","isEnabled":true,"limit":60,"resumeLevel":40,"somethingNew":true}
        """
        let rule = try JSONDecoder().decode(AutomationRule.self, from: Data(json.utf8))
        #expect(rule.resumeLevel == 40)
    }

    // MARK: - Reading the level back

    @Test func aRuleWithAResumeLevelSailsBetweenItsOwnLevels() {
        #expect(AutomationRule(limit: 90, resumeLevel: 50).sailingLevels == SailingLevels(limit: 90, resumeLevel: 50))
    }

    @Test func aRuleWithoutAResumeLevelDoesNotSail() {
        #expect(AutomationRule(limit: 90).sailingLevels == nil)
    }

    @Test func aResumeLevelLeftAboveALoweredLimitIsPushedFiveBelowIt() {
        #expect(AutomationRule(limit: 60, resumeLevel: 70).sailingLevels == SailingLevels(limit: 60, resumeLevel: 55))
        #expect(AutomationRule(limit: 60, resumeLevel: 60).sailingLevels == SailingLevels(limit: 60, resumeLevel: 55))
    }

    @Test func aResumeLevelBelowTheFloorIsRaisedToIt() {
        #expect(AutomationRule(limit: 80, resumeLevel: 5).sailingLevels == SailingLevels(limit: 80, resumeLevel: 20))
        #expect(AutomationRule(limit: 80, resumeLevel: -40).sailingLevels == SailingLevels(limit: 80, resumeLevel: 20))
    }

    @Test func anOffStepResumeLevelSnapsToTheNearestStep() {
        #expect(AutomationRule(limit: 80, resumeLevel: 63).sailingLevels == SailingLevels(limit: 80, resumeLevel: 65))
        #expect(AutomationRule(limit: 80, resumeLevel: 62).sailingLevels == SailingLevels(limit: 80, resumeLevel: 60))
    }

    @Test func aRuleBelowTwentyFiveDoesNotSail() {
        #expect(AutomationRule(limit: 24, resumeLevel: 20).sailingLevels == nil)
        #expect(AutomationRule(limit: 0, resumeLevel: 20).sailingLevels == nil)
        #expect(AutomationRule(limit: 25, resumeLevel: 20).sailingLevels == SailingLevels(limit: 25, resumeLevel: 20))
    }

    @Test func onlyALimitOfTwentyFiveOrMoreCanSail() {
        #expect(SailingRange.canSail(limit: 25))
        #expect(SailingRange.canSail(limit: 50))
        #expect(!SailingRange.canSail(limit: 24))
        #expect(!SailingRange.canSail(limit: 0))
    }

    @Test func theRuleResumeLevelIsJudgedAgainstTheLimitItIsEnforcedAt() {
        // A 60% rule on a Mac that enforces 80% at the least: the rule's own level still counts.
        #expect(SailingRange.ruleResumeLevel(limit: 80, stored: 50) == 50)
        #expect(SailingRange.ruleResumeLevel(limit: 80, stored: nil) == nil)
    }

    // MARK: - What the charging state carries

    @Test func theTargetCarriesTheStoredLevels() {
        let target = AutomationTarget(rule: AutomationRule(name: "Work", limit: 90, resumeLevel: 50))
        #expect(target == AutomationTarget(limit: 90, resumeLevel: 50))
        #expect(AutomationTarget(rule: AutomationRule(limit: 70)).resumeLevel == nil)
    }
}
