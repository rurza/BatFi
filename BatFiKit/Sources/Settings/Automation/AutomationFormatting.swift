//
//  AutomationFormatting.swift
//  BatFi
//
//  Human-readable summaries for automation rules — used in the settings list rows and the
//  menu label.
//

import AppShared
import Foundation
import L10n

public enum AutomationFormatting {
    /// "60% · Weekdays 9:00–18:00 · @ Office"
    public static func summary(for rule: AutomationRule) -> String {
        var parts: [String] = [L10n.Automation.limitFragment(rule.limit)]
        parts.append(scheduleSummary(rule.schedule))
        parts.append(locationSummary(rule.location))
        return parts.joined(separator: " · ")
    }

    public static func scheduleSummary(_ schedule: Schedule?) -> String {
        guard let schedule else { return L10n.Automation.anyTime }
        switch schedule {
        case let .recurring(days, time):
            return "\(daysSummary(days)) \(timeRange(time))"
        case let .oneOff(day, time):
            return "\(dateString(day)) \(timeRange(time))"
        }
    }

    public static func locationSummary(_ fence: GeoFence?) -> String {
        guard let fence else { return L10n.Automation.anywhere }
        let label = fence.label.isEmpty ? L10n.Automation.locationLabelPlaceholder : fence.label
        return "@ \(label)"
    }

    public static func daysSummary(_ days: Set<Weekday>) -> String {
        if days.count == 7 { return L10n.Automation.daysEveryDay }
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weekend: Set<Weekday> = [.saturday, .sunday]
        if days == weekdays { return L10n.Automation.daysWeekdays }
        if days == weekend { return L10n.Automation.daysWeekends }
        let ordered = Weekday.localizedOrder().filter { days.contains($0) }
        return ordered.map(shortName).joined(separator: ", ")
    }

    public static func timeRange(_ range: TimeRange) -> String {
        "\(time(range.start))–\(time(range.end))"
    }

    public static func time(_ tod: TimeOfDay) -> String {
        String(format: "%d:%02d", tod.hour, tod.minute)
    }

    // Weekday enum is numbered to match Calendar (1 = Sunday), and the symbol arrays are
    // also Sunday-first, so `rawValue - 1` indexes them directly. Using the calendar's
    // localized symbols means day names/letters localize for free.
    public static func shortName(_ weekday: Weekday) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols[weekday.rawValue - 1]
    }

    public static func singleLetter(_ weekday: Weekday) -> String {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return symbols[weekday.rawValue - 1]
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    public static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
