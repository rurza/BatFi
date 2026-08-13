//
//  ChartMarkIntervalTests.swift
//  BatFi
//
//  Unit tests for the pure chart-mark interval policy.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChartMarkIntervalTests {
    private typealias Interval = ChartMarkInterval

    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func usesTheNaturalEndWhenItIsAfterTheStart() {
        let range = Interval.range(start: start, naturalEnd: start.addingTimeInterval(60))
        #expect(range.lowerBound == start)
        #expect(range.upperBound == start.addingTimeInterval(60))
    }

    @Test func fallsBackToAMinimumWidthWhenThereIsNoNaturalEnd() {
        let range = Interval.range(start: start, naturalEnd: nil)
        #expect(range.lowerBound == start)
        #expect(range.upperBound == start.addingTimeInterval(Interval.minimumWidth))
    }

    /// The crash this policy exists to prevent (Sentry BATFI-1E, 26 users, ~2900 events).
    ///
    /// `ChartsView` feeds these bounds into `point.timestamp ..< offsetDate`, and `Range`
    /// traps with "Range requires lowerBound <= upperBound" when the end precedes the
    /// start. The last point on the chart takes `Date.now` as its natural end, which is
    /// read at *render* time while the point's timestamp was read at *fetch* time — so a
    /// backwards wall-clock correction between the two (routine after a laptop wakes and
    /// re-syncs NTP) puts "now" behind the timestamp and kills the app.
    @Test func clampsANaturalEndThatPrecedesTheStart() {
        let range = Interval.range(start: start, naturalEnd: start.addingTimeInterval(-3600))
        #expect(range.lowerBound == start)
        #expect(range.upperBound == start.addingTimeInterval(Interval.minimumWidth))
    }

    /// An equal end makes a legal-but-degenerate empty range. Widen it too, so every mark
    /// the chart draws has some extent.
    @Test func clampsANaturalEndEqualToTheStart() {
        let range = Interval.range(start: start, naturalEnd: start)
        #expect(range.upperBound == start.addingTimeInterval(Interval.minimumWidth))
    }

    /// The whole guarantee in one place: whatever the caller computes as the natural end,
    /// the returned range is constructible and non-empty.
    @Test(arguments: [-86400.0, -3600, -0.1, 0, 0.05, 1, 3600] as [TimeInterval])
    func upperBoundIsAlwaysStrictlyAfterTheStart(offset: TimeInterval) {
        let range = Interval.range(start: start, naturalEnd: start.addingTimeInterval(offset))
        #expect(range.upperBound > range.lowerBound)
    }

    @Test func distantPastNaturalEndIsStillClamped() {
        let range = Interval.range(start: start, naturalEnd: .distantPast)
        #expect(range.upperBound > range.lowerBound)
    }
}
