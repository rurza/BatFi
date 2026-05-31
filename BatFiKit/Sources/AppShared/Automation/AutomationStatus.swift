//
//  AutomationStatus.swift
//  BatFi
//
//  Snapshot of the automation engine's current state, consumed by the menu label.
//

import Foundation

public struct AutomationStatus: Equatable, Sendable {
    public var enabled: Bool
    /// The rule currently driving the charge limit, if any.
    public var activeRule: AutomationRule?
    /// The soonest upcoming scheduled rule, if any.
    public var nextRule: AutomationRule?
    /// When `nextRule` will next become active.
    public var nextDate: Date?

    public init(
        enabled: Bool = false,
        activeRule: AutomationRule? = nil,
        nextRule: AutomationRule? = nil,
        nextDate: Date? = nil
    ) {
        self.enabled = enabled
        self.activeRule = activeRule
        self.nextRule = nextRule
        self.nextDate = nextDate
    }
}
