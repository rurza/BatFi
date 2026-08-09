//
//  AutomationEngineTests.swift
//  BatFi
//
//  Unit tests for the pure automation resolution logic.
//

import Foundation
import Testing

@testable import AppShared

private let utc = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// Build a UTC date for the given components.
private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var dc = DateComponents()
    dc.year = year; dc.month = month; dc.day = day; dc.hour = hour; dc.minute = minute
    return utc.date(from: dc)!
}

private func range(_ sh: Int, _ sm: Int, _ eh: Int, _ em: Int) -> TimeRange {
    TimeRange(start: TimeOfDay(hour: sh, minute: sm), end: TimeOfDay(hour: eh, minute: em))
}

@Suite struct TimeRangeTests {
    @Test func sameDayWindowContains() {
        let r = range(9, 0, 18, 0)
        #expect(r.contains(TimeOfDay(hour: 9, minute: 0)))
        #expect(r.contains(TimeOfDay(hour: 13, minute: 30)))
        #expect(r.contains(TimeOfDay(hour: 18, minute: 0)))
        #expect(!r.contains(TimeOfDay(hour: 8, minute: 59)))
        #expect(!r.contains(TimeOfDay(hour: 18, minute: 1)))
    }

    @Test func overnightWindowWraps() {
        let r = range(22, 0, 2, 0)
        #expect(r.contains(TimeOfDay(hour: 23, minute: 0)))
        #expect(r.contains(TimeOfDay(hour: 1, minute: 0)))
        #expect(r.contains(TimeOfDay(hour: 2, minute: 0)))
        #expect(!r.contains(TimeOfDay(hour: 3, minute: 0)))
        #expect(!r.contains(TimeOfDay(hour: 21, minute: 59)))
    }
}

@Suite struct ScheduleMatchingTests {
    // 2026-06-01 is a Monday.
    @Test func recurringMatchesSelectedWeekdayWithinWindow() {
        let s = Schedule.recurring(days: [.monday, .friday], time: range(9, 0, 17, 0))
        #expect(s.matches(date(2026, 6, 1, 10, 0), calendar: utc))   // Mon 10:00
        #expect(!s.matches(date(2026, 6, 1, 8, 0), calendar: utc))   // Mon before window
        #expect(!s.matches(date(2026, 6, 2, 10, 0), calendar: utc))  // Tue, not selected
        #expect(s.matches(date(2026, 6, 5, 16, 59), calendar: utc))  // Fri within window
    }

    @Test func oneOffMatchesOnlyThatDay() {
        let s = Schedule.oneOff(day: date(2026, 6, 5, 0, 0), time: range(8, 0, 9, 0))
        #expect(s.matches(date(2026, 6, 5, 8, 30), calendar: utc))
        #expect(!s.matches(date(2026, 6, 6, 8, 30), calendar: utc)) // next day
        #expect(!s.matches(date(2026, 6, 5, 9, 30), calendar: utc)) // outside window
    }

    @Test func nextStartFindsUpcomingRecurring() {
        let s = Schedule.recurring(days: [.wednesday], time: range(9, 0, 10, 0))
        // From Monday 2026-06-01 12:00, next Wednesday is 2026-06-03 09:00.
        let next = s.nextStart(after: date(2026, 6, 1, 12, 0), calendar: utc)
        #expect(next == date(2026, 6, 3, 9, 0))
    }

    @Test func nextStartNilForPastOneOff() {
        let s = Schedule.oneOff(day: date(2026, 6, 1, 0, 0), time: range(8, 0, 9, 0))
        #expect(s.nextStart(after: date(2026, 6, 2, 0, 0), calendar: utc) == nil)
    }
}

@Suite struct GeoFenceTests {
    @Test func containsWithinRadius() {
        let center = Coordinate(latitude: 52.2297, longitude: 21.0122) // Warsaw
        let fence = GeoFence(center: center, radiusMeters: 500)
        let near = Coordinate(latitude: 52.2300, longitude: 21.0125)   // ~40 m away
        let far = Coordinate(latitude: 52.4000, longitude: 21.0122)    // ~19 km away
        #expect(fence.contains(near))
        #expect(!fence.contains(far))
    }
}

@Suite struct ActiveRuleResolutionTests {
    private func rule(
        _ name: String,
        limit: Int,
        enabled: Bool = true,
        schedule: Schedule? = nil,
        location: GeoFence? = nil
    ) -> AutomationRule {
        AutomationRule(name: name, isEnabled: enabled, limit: limit, schedule: schedule, location: location)
    }

    @Test func disabledFeatureYieldsNil() {
        let rules = [rule("always", limit: 60)]
        #expect(AutomationEngine.activeRule(in: rules, enabled: false, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [], calendar: utc) == nil)
    }

    @Test func topMostMatchingRuleWins() {
        let rules = [
            rule("first", limit: 100, schedule: .recurring(days: [.monday], time: range(0, 0, 23, 59))),
            rule("second", limit: 60, schedule: .recurring(days: [.monday], time: range(0, 0, 23, 59))),
        ]
        let active = AutomationEngine.activeRule(in: rules, enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [], calendar: utc)
        #expect(active?.name == "first")
    }

    @Test func skipsDisabledRule() {
        let rules = [
            rule("disabled", limit: 100, enabled: false),
            rule("enabled", limit: 60),
        ]
        let active = AutomationEngine.activeRule(in: rules, enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [], calendar: utc)
        #expect(active?.name == "enabled")
    }

    @Test func locationRuleFailsWhenFenceUnsatisfied() {
        let fence = GeoFence(center: Coordinate(latitude: 52.2297, longitude: 21.0122), radiusMeters: 300)
        let rules = [rule("office", limit: 60, location: fence)]
        // Empty set models both "not yet resolved" (.unknown) and "outside".
        #expect(AutomationEngine.activeRule(in: rules, enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [], calendar: utc) == nil)
    }

    @Test func locationRuleMatchesWhenItsOwnFenceIsSatisfied() {
        let fence = GeoFence(center: Coordinate(latitude: 52.2297, longitude: 21.0122), radiusMeters: 300)
        let r = rule("office", limit: 60, location: fence)
        #expect(AutomationEngine.activeRule(in: [r], enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [r.id], calendar: utc)?.name == "office")
    }

    @Test func anotherRulesSatisfiedFenceDoesNotMatch() {
        let fence = GeoFence(center: Coordinate(latitude: 52.2297, longitude: 21.0122), radiusMeters: 300)
        let r = rule("office", limit: 60, location: fence)
        let unrelated = UUID()
        #expect(AutomationEngine.activeRule(in: [r], enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [unrelated], calendar: utc) == nil)
    }

    @Test func scheduleAndLocationCombineWithAnd() {
        let fence = GeoFence(center: Coordinate(latitude: 52.2297, longitude: 21.0122), radiusMeters: 300)
        let r = rule("office hours", limit: 60,
                     schedule: .recurring(days: [.monday], time: range(9, 0, 17, 0)),
                     location: fence)
        // Right time + right place → active.
        #expect(AutomationEngine.activeRule(in: [r], enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [r.id], calendar: utc)?.name == "office hours")
        // Right time, wrong place → inactive.
        #expect(AutomationEngine.activeRule(in: [r], enabled: true, at: date(2026, 6, 1, 10, 0), satisfiedFenceIDs: [], calendar: utc) == nil)
        // Wrong time, right place → inactive.
        #expect(AutomationEngine.activeRule(in: [r], enabled: true, at: date(2026, 6, 1, 20, 0), satisfiedFenceIDs: [r.id], calendar: utc) == nil)
    }

    @Test func unconditionalRuleIsAlwaysActiveWhenEnabled() {
        let r = rule("fallback", limit: 50)
        #expect(r.isUnconditional)
        #expect(AutomationEngine.activeRule(in: [r], enabled: true, at: date(2026, 6, 1, 3, 0), satisfiedFenceIDs: [], calendar: utc)?.name == "fallback")
    }
}

/// Resolving the published active-rule ID back to a rule. The Charging pane, the menu and the
/// notifications all read this to decide whether to say anything at all, so it has to answer
/// the same way for all three.
@Suite struct PublishedActiveRuleTests {
    private func rule(_ name: String, enabled: Bool = true) -> AutomationRule {
        AutomationRule(name: name, isEnabled: enabled, limit: 60)
    }

    @Test func emptyIDMeansNothingIsActive() {
        #expect(AutomationEngine.activeRule(in: [rule("work")], activeRuleID: "") == nil)
    }

    @Test func resolvesTheNamedRule() {
        let work = rule("work")
        let home = rule("home")
        #expect(AutomationEngine.activeRule(in: [home, work], activeRuleID: work.id.uuidString)?.name == "work")
    }

    @Test func ruleTurnedOffSinceItWasPublishedIsNotActive() {
        let work = rule("work", enabled: false)
        #expect(AutomationEngine.activeRule(in: [work], activeRuleID: work.id.uuidString) == nil)
    }

    @Test func deletedRuleIsNotActive() {
        let deleted = rule("work")
        #expect(AutomationEngine.activeRule(in: [rule("home")], activeRuleID: deleted.id.uuidString) == nil)
    }
}
