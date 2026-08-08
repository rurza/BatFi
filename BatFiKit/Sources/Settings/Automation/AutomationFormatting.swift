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

    /// The location condition, described by what it constrains rather than by a name.
    ///
    /// A fence used to carry its own label and this read "@ Office". That label was a second
    /// name for something the rule already names, and every surface showing this summary
    /// shows the rule's name beside it — so a rule called "Dom" fenced to a place called
    /// "Dom" said "Dom" twice and told the reader nothing either time.
    ///
    /// The radius is the part that was never shown and is the one thing here a rule's name
    /// cannot imply.
    public static func locationSummary(_ fence: GeoFence?) -> String {
        guard let fence else { return L10n.Automation.anywhere }
        return L10n.Automation.withinRadius(radius(fence.radiusMeters))
    }

    /// - Note: uses the fence's stored radius, not the monitored one. The picker clamps to
    ///   `GeoFence.minimumMonitoredRadiusMeters` on the way in, so the two agree for anything
    ///   this app has written; a legacy rule holding a tighter radius is reported as it was
    ///   saved rather than silently restated.
    public static func radius(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        // Metres, not `.naturalScale`. The scale option is the tempting one — it would say
        // "328 yd" to a US reader — but the picker's own slider readout is metres, so the
        // rule list would then disagree with the editor the user set it in, for the same
        // fence. Converting one and not the other is worse than not converting either;
        // moving the whole radius UI to local units is a separate job.
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return formatter.string(from: Measurement(value: meters, unit: UnitLength.meters))
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
