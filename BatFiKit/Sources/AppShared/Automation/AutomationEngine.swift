//
//  AutomationEngine.swift
//  BatFi
//
//  Pure resolution of "which rule wins right now" and "what fires next". No side effects,
//  no system dependencies — the runtime engine (AppCore) wraps this with clocks and
//  CoreLocation.
//

import Foundation

public enum AutomationEngine {
    /// The first enabled rule (in list order = priority) whose conditions match. Returns nil
    /// when automation is disabled or nothing matches.
    public static func activeRule(
        in rules: [AutomationRule],
        enabled: Bool,
        at date: Date,
        location: Coordinate?,
        calendar: Calendar = .current
    ) -> AutomationRule? {
        guard enabled else { return nil }
        return rules.first { $0.matches(at: date, location: location, calendar: calendar) }
    }

    /// The soonest upcoming schedule start across all enabled, scheduled rules, paired with
    /// the rule it belongs to. Used for the menu's "next" hint. Rules without a schedule are
    /// ignored here (they have no future start to announce).
    public static func nextScheduled(
        in rules: [AutomationRule],
        enabled: Bool,
        after date: Date,
        calendar: Calendar = .current
    ) -> (rule: AutomationRule, start: Date)? {
        guard enabled else { return nil }
        var best: (rule: AutomationRule, start: Date)?
        for rule in rules where rule.isEnabled {
            guard let schedule = rule.schedule,
                  let start = schedule.nextStart(after: date, calendar: calendar) else { continue }
            if best == nil || start < best!.start {
                best = (rule, start)
            }
        }
        return best
    }
}
