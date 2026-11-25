//
//  AutomationRule.swift
//  BatFi
//
//  One automation rule: apply a charge limit — and, when the rule sails, its own resume level —
//  when an optional schedule AND an optional location both match. Stored as an ordered list
//  where earlier rules win.
//

import Foundation

public struct AutomationRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Charge limit to apply while this rule is active, 0...100.
    public var limit: Int
    /// The rule's own second charge level: charge again only below it. `nil` means the rule
    /// does not sail. As stored, which can be stale or out of range — read it through
    /// `sailingLevels`, which corrects it. Absent from rules saved before sailing, and left out
    /// of the encoding while nil, so those rules read back exactly as they were written.
    public var resumeLevel: Int?
    /// Time condition. `nil` means "any time".
    public var schedule: Schedule?
    /// Location condition. `nil` means "anywhere".
    public var location: GeoFence?

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        limit: Int = 80,
        resumeLevel: Int? = nil,
        schedule: Schedule? = nil,
        location: GeoFence? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.limit = limit
        self.resumeLevel = resumeLevel
        self.schedule = schedule
        self.location = location
    }

    /// The levels this rule sails between, its stored resume level corrected against its limit;
    /// nil when it does not sail.
    public var sailingLevels: SailingLevels? {
        SailingRange.ruleResumeLevel(limit: limit, stored: resumeLevel)
            .map { SailingLevels(limit: limit, resumeLevel: $0) }
    }

    /// True when this rule defines no conditions — it is always active while enabled.
    public var isUnconditional: Bool {
        schedule == nil && location == nil
    }

    /// Whether this rule's conditions are satisfied. A location condition is confirmed by
    /// CoreLocation reporting this rule's own fence as satisfied; an absent ID means either
    /// "outside" or "not yet resolved", and both fail closed.
    public func matches(at date: Date, satisfiedFenceIDs: Set<UUID>, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        if let schedule, !schedule.matches(date, calendar: calendar) { return false }
        if location != nil, !satisfiedFenceIDs.contains(id) { return false }
        return true
    }
}

/// What an active rule puts in force, as the charging state carries it: the rule's limit and
/// its stored resume level (nil when it does not sail). The level is corrected where it is
/// used, against the limit actually requested (`SailingRange.levelsInPlay`).
public struct AutomationTarget: Equatable, Sendable {
    public let limit: Int
    public let resumeLevel: Int?

    public init(limit: Int, resumeLevel: Int? = nil) {
        self.limit = limit
        self.resumeLevel = resumeLevel
    }

    public init(rule: AutomationRule) {
        self.init(limit: rule.limit, resumeLevel: rule.resumeLevel)
    }
}
