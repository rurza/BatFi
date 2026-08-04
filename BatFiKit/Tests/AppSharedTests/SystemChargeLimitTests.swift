//
//  SystemChargeLimitTests.swift
//  BatFi
//
//  The one rule that matters here is direction: a limit the mechanism cannot
//  express must be raised, never lowered. Rounding down would charge the battery
//  past the point the user chose, which is the failure this backend exists to avoid.
//

import Foundation
import Testing

@testable import Shared

@Suite struct SystemChargeLimitTests {
    /// What PowerUI reports on the machines measured so far.
    private let apple = [80, 85, 90, 95, 100]

    @Test func acceptedValuesArePassedThroughUnchanged() {
        for value in apple {
            #expect(SystemChargeLimit.applicableLimit(for: value, from: apple) == value)
        }
    }

    /// The case that motivates the whole backend: a sub-80% limit cannot be honoured.
    @Test func aRequestBelowTheRangeRisesToTheLowestAcceptedValue() {
        #expect(SystemChargeLimit.applicableLimit(for: 55, from: apple) == 80)
        #expect(SystemChargeLimit.applicableLimit(for: 79, from: apple) == 80)
        #expect(SystemChargeLimit.applicableLimit(for: 1, from: apple) == 80)
    }

    @Test func aRequestBetweenStepsRisesToTheNextStep() {
        #expect(SystemChargeLimit.applicableLimit(for: 81, from: apple) == 85)
        #expect(SystemChargeLimit.applicableLimit(for: 86, from: apple) == 90)
        #expect(SystemChargeLimit.applicableLimit(for: 94, from: apple) == 95)
        #expect(SystemChargeLimit.applicableLimit(for: 96, from: apple) == 100)
    }

    /// Nothing above the top of the range is expressible, so it clamps down — the only
    /// direction this may ever go down, and only to the maximum the hardware allows.
    @Test func aRequestAboveTheRangeClampsToTheHighestAcceptedValue() {
        #expect(SystemChargeLimit.applicableLimit(for: 101, from: apple) == 100)
        #expect(SystemChargeLimit.applicableLimit(for: 200, from: apple) == 100)
    }

    /// The accepted list is queried from PowerUI, so its order is not ours to assume.
    @Test func anUnorderedAcceptedListStillRoundsUp() {
        let shuffled = [100, 80, 95, 85, 90]
        #expect(SystemChargeLimit.applicableLimit(for: 82, from: shuffled) == 85)
        #expect(SystemChargeLimit.applicableLimit(for: 55, from: shuffled) == 80)
    }

    /// An empty list means the accepted values could not be read. Guessing one would
    /// mean writing a made-up number into a setting the user can see.
    @Test func noAcceptedValuesYieldsNoAnswer() {
        #expect(SystemChargeLimit.applicableLimit(for: 80, from: []) == nil)
    }

    /// A future macOS that widens the range must work without a code change.
    @Test func aWiderAcceptedRangeIsHonoured() {
        let wider = [50, 60, 70, 80, 90, 100]
        #expect(SystemChargeLimit.applicableLimit(for: 55, from: wider) == 60)
        #expect(SystemChargeLimit.applicableLimit(for: 50, from: wider) == 50)
    }

    /// The invariant itself, over every limit BatFi's UI can produce.
    @Test func neverRoundsDownWithinTheExpressibleRange() {
        for requested in 1 ... 100 {
            let applied = SystemChargeLimit.applicableLimit(for: requested, from: apple)
            #expect(applied.map { $0 >= requested } == true, "\(requested)% was lowered")
        }
    }
}
