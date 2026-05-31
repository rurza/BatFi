//
//  Schedule.swift
//  BatFi
//
//  Time-based half of an automation rule's conditions.
//

import Foundation

/// A point in the day, resolution of one minute.
public struct TimeOfDay: Codable, Equatable, Comparable, Sendable {
    public var hour: Int   // 0...23
    public var minute: Int // 0...59

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesOfDay: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesOfDay < rhs.minutesOfDay
    }
}

/// A start/end window within a day. Supports overnight wrap (start later than end),
/// e.g. 22:00 → 02:00.
public struct TimeRange: Codable, Equatable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay

    public init(start: TimeOfDay, end: TimeOfDay) {
        self.start = start
        self.end = end
    }

    public func contains(_ time: TimeOfDay) -> Bool {
        let s = start.minutesOfDay
        let e = end.minutesOfDay
        let m = time.minutesOfDay
        if s <= e {
            return m >= s && m <= e
        } else {
            // Overnight window: matches the evening tail and the early-morning head.
            return m >= s || m <= e
        }
    }
}

/// Day of week, numbered to match `Calendar`'s `.weekday` component (1 = Sunday).
public enum Weekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    public var id: Int { rawValue }

    /// Monday-first ordering, useful for display.
    public static let displayOrder: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday,
    ]
}

/// When a rule's time condition is satisfied.
public enum Schedule: Codable, Equatable, Sendable {
    /// Fires once, on the calendar day of `day`, while the clock is within `time`.
    case oneOff(day: Date, time: TimeRange)
    /// Fires on each of `days`, while the clock is within `time`.
    case recurring(days: Set<Weekday>, time: TimeRange)

    /// Whether `date` falls within this schedule.
    ///
    /// Note (v1 simplification): an overnight `recurring` window is evaluated against the
    /// weekday the clock reads, so selecting Friday 22:00–02:00 matches Friday evening and
    /// Friday's own early morning — not Saturday's. Documented and acceptable for v1.
    public func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekdayNum = comps.weekday,
              let hour = comps.hour,
              let minute = comps.minute else { return false }
        let now = TimeOfDay(hour: hour, minute: minute)

        switch self {
        case let .recurring(days, time):
            guard let weekday = Weekday(rawValue: weekdayNum), days.contains(weekday) else {
                return false
            }
            return time.contains(now)
        case let .oneOff(day, time):
            guard calendar.isDate(date, inSameDayAs: day) else { return false }
            return time.contains(now)
        }
    }

    /// The next moment (at or after `date`) this schedule's window *starts*, scanning up to
    /// two weeks ahead. Used for the menu's "next" hint. Returns nil if nothing upcoming.
    public func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        let time: TimeRange
        switch self {
        case let .oneOff(_, t): time = t
        case let .recurring(_, t): time = t
        }
        for dayOffset in 0...14 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            guard matchesDay(candidateDay, calendar: calendar) else { continue }
            var dc = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            dc.hour = time.start.hour
            dc.minute = time.start.minute
            dc.second = 0
            guard let start = calendar.date(from: dc) else { continue }
            if start > date { return start }
        }
        return nil
    }

    /// Whether the schedule applies to the calendar day of `date` (ignoring the clock).
    private func matchesDay(_ date: Date, calendar: Calendar) -> Bool {
        switch self {
        case let .oneOff(day, _):
            return calendar.isDate(date, inSameDayAs: day)
        case let .recurring(days, _):
            let num = calendar.component(.weekday, from: date)
            guard let weekday = Weekday(rawValue: num) else { return false }
            return days.contains(weekday)
        }
    }
}
