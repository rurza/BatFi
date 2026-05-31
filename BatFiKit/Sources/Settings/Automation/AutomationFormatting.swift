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

enum AutomationFormatting {
    /// "60% · Weekdays 9:00–18:00 · @ Office"
    static func summary(for rule: AutomationRule) -> String {
        var parts: [String] = [L10n.Automation.limitFragment(rule.limit)]
        parts.append(scheduleSummary(rule.schedule))
        parts.append(locationSummary(rule.location))
        return parts.joined(separator: " · ")
    }

    static func scheduleSummary(_ schedule: Schedule?) -> String {
        guard let schedule else { return L10n.Automation.anyTime }
        switch schedule {
        case let .recurring(days, time):
            return "\(daysSummary(days)) \(timeRange(time))"
        case let .oneOff(day, time):
            return "\(dateString(day)) \(timeRange(time))"
        }
    }

    static func locationSummary(_ fence: GeoFence?) -> String {
        guard let fence else { return L10n.Automation.anywhere }
        let label = fence.label.isEmpty ? L10n.Automation.locationLabelPlaceholder : fence.label
        return "@ \(label)"
    }

    static func daysSummary(_ days: Set<Weekday>) -> String {
        if days.count == 7 { return "Every day" }
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let weekend: Set<Weekday> = [.saturday, .sunday]
        if days == weekdays { return "Weekdays" }
        if days == weekend { return "Weekends" }
        let ordered = Weekday.displayOrder.filter { days.contains($0) }
        return ordered.map(shortName).joined(separator: ", ")
    }

    static func timeRange(_ range: TimeRange) -> String {
        "\(time(range.start))–\(time(range.end))"
    }

    static func time(_ tod: TimeOfDay) -> String {
        String(format: "%d:%02d", tod.hour, tod.minute)
    }

    static func shortName(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "Mon"
        case .tuesday: return "Tue"
        case .wednesday: return "Wed"
        case .thursday: return "Thu"
        case .friday: return "Fri"
        case .saturday: return "Sat"
        case .sunday: return "Sun"
        }
    }

    static func singleLetter(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: return "M"
        case .tuesday: return "T"
        case .wednesday: return "W"
        case .thursday: return "T"
        case .friday: return "F"
        case .saturday: return "S"
        case .sunday: return "S"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
