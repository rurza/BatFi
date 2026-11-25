//
//  FenceReconciliation.swift
//  BatFi
//
//  Pure diff between the fences that should be monitored and the ones CoreLocation is already
//  monitoring. Kept free of CoreLocation so the decision — especially "change nothing" — is
//  unit-testable.
//

import Foundation

public enum FenceReconciliation {
    public struct Plan: Sendable, Equatable {
        /// Applied before `toAdd`, so a changed fence is replaced rather than duplicated.
        public var toRemove: [UUID]
        public var toAdd: [MonitoredFence]

        public init(toRemove: [UUID] = [], toAdd: [MonitoredFence] = []) {
            self.toRemove = toRemove
            self.toAdd = toAdd
        }

        public var isEmpty: Bool { toRemove.isEmpty && toAdd.isEmpty }
    }

    /// - Parameters:
    ///   - desired: fences that should be monitored right now.
    ///   - current: regions CoreLocation is monitoring, keyed by identifier.
    ///
    /// An entry present in both with an unchanged region is omitted from the plan entirely.
    /// That case is the reason this function exists: re-adding a condition resets its
    /// monitoring state to `.unknown`, which would flicker a matching rule off.
    public static func plan(desired: [MonitoredFence], current: [UUID: MonitoredRegion]) -> Plan {
        var toRemove: [UUID] = []
        var toAdd: [MonitoredFence] = []
        // `desired` is derived from rules decoded out of UserDefaults JSON, so a duplicate ID is
        // not structurally impossible. `uniqueKeysWithValues` would trap — a `fatalError` on an
        // actor path fed by user-writable data. First entry wins instead, and the loop below
        // skips later repeats so one ID cannot be submitted twice in a single pass.
        let desiredByID = Dictionary(desired.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for id in current.keys where desiredByID[id] == nil {
            toRemove.append(id)
        }

        var seen: Set<UUID> = []
        for fence in desired where seen.insert(fence.id).inserted {
            guard let existing = current[fence.id] else {
                toAdd.append(fence)
                continue
            }
            if !existing.matches(fence.region) {
                toRemove.append(fence.id)
                toAdd.append(fence)
            }
        }

        return Plan(toRemove: toRemove, toAdd: toAdd)
    }
}
