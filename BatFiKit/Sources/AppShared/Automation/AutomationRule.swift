//
//  AutomationRule.swift
//  BatFi
//
//  One automation rule: apply a charge limit when an optional schedule AND an optional
//  location both match. Stored as an ordered list where earlier rules win.
//

import Foundation

public struct AutomationRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    /// Charge limit to apply while this rule is active, 0...100.
    public var limit: Int
    /// Time condition. `nil` means "any time".
    public var schedule: Schedule?
    /// Location condition. `nil` means "anywhere".
    public var location: GeoFence?

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        limit: Int = 80,
        schedule: Schedule? = nil,
        location: GeoFence? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.limit = limit
        self.schedule = schedule
        self.location = location
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
