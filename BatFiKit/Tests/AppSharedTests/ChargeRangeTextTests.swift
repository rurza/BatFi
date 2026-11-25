//
//  ChargeRangeTextTests.swift
//  BatFi
//
//  How a rule's levels are printed: the range for a rule that sails, its limit otherwise, the
//  range written in the same style as the single percentage printed beside it.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeRangeTextTests {
    private let spaced: (Int) -> String = { "\($0) %" }
    private let leading: (Int) -> String = { "%\($0)" }

    @Test func aSingleLimitIsTheHardCodedPercentageByDefault() {
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: nil) == "80%")
    }

    @Test func aRangePrintsThePercentSignOnce() {
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: 70) == "70–80%")
    }

    @Test func aSingleLimitIsTheGivenPercentageUntouched() {
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: nil, percentage: spaced) == "80 %")
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: nil, percentage: leading) == "%80")
    }

    @Test func aRangeKeepsTheSpaceTheSinglePercentageHas() {
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: 70, percentage: spaced) == "70–80 %")
    }

    @Test func aRangeKeepsALeadingSignWhereTheSinglePercentageHasOne() {
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: 70, percentage: leading) == "%70–80")
    }

    @Test func aRangeIgnoresTheLocalesOwnPercentStyle() {
        // The app's French-region formatter would say "80 %"; the sibling here says "80%".
        #expect(ChargeRangeText.text(limit: 80, resumeLevel: 70, percentage: { "\($0)%" }) == "70–80%")
    }

    @Test func aRulePrintsItsCorrectedLevels() {
        #expect(ChargeRangeText.text(for: AutomationRule(limit: 80, resumeLevel: 90)) == "75–80%")
        #expect(ChargeRangeText.text(for: AutomationRule(limit: 80)) == "80%")
        #expect(ChargeRangeText.text(for: AutomationRule(limit: 20, resumeLevel: 20)) == "20%")
        #expect(ChargeRangeText.text(for: AutomationRule(limit: 80, resumeLevel: 70), percentage: leading) == "%70–80")
    }
}
