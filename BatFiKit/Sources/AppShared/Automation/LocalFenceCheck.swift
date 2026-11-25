//
//  LocalFenceCheck.swift
//  BatFi
//
//  Fence membership decided by BatFi itself from a one-shot fix. CLMonitor stays the primary
//  source, but on some Macs its event stream stays alive and never delivers, so rules cannot
//  depend on it alone. Pure, with no CoreLocation dependency, so the decision is unit-tested.
//

import Foundation

/// One location fix, reduced to what the fence decision needs.
public struct LocationFix: Sendable, Equatable {
    public var coordinate: Coordinate
    /// Radius of uncertainty in meters. CoreLocation reports a negative value for an invalid fix.
    public var horizontalAccuracy: Double
    public var timestamp: Date

    public init(coordinate: Coordinate, horizontalAccuracy: Double, timestamp: Date) {
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }
}

/// What a local check concluded about one fence, kept so a later reseed from CLMonitor's
/// persisted (and possibly stale) record does not overwrite newer evidence.
public struct LocalFenceVerdict: Sendable, Equatable {
    public var inside: Bool
    public var date: Date

    public init(inside: Bool, date: Date) {
        self.inside = inside
        self.date = date
    }
}

/// Why a local check ran. Logged, so a customer log shows what drove each decision.
public enum FenceCheckReason: String, Sendable {
    case launch
    case fencesChanged = "fences changed"
    case authorized
    case wake
    case networkChange = "network change"
    case periodic
}

public enum LocalFenceCheck {
    /// A fix coarser than this says almost nothing about a few-hundred-metre fence.
    public static let maximumUsableAccuracyMeters: Double = 1_000

    public enum Verdict: String, Sendable {
        case inside, outside, uncertain
    }

    /// Fresh means taken after the request began: CoreLocation delivers its cached location
    /// first, which is not evidence of where the Mac is now.
    public static func isUsable(_ fix: LocationFix, requestedAt: Date) -> Bool {
        hasUsableAccuracy(fix) && fix.timestamp >= requestedAt
    }

    static func hasUsableAccuracy(_ fix: LocationFix) -> Bool {
        let accuracy = fix.horizontalAccuracy
        return accuracy.isFinite && accuracy >= 0 && accuracy <= maximumUsableAccuracyMeters
    }

    /// Inside when the best estimate is inside; outside only when even the near edge of the
    /// uncertainty circle is outside. The band in between keeps the previous state, so a fix
    /// wobbling around the boundary cannot flap the rule.
    ///
    /// Measured against the monitored radius, so this agrees with what CLMonitor evaluates.
    public static func verdict(for fence: MonitoredFence, fix: LocationFix) -> Verdict {
        let region = fence.region
        let distance = region.center.distance(to: fix.coordinate)
        if distance <= region.radiusMeters { return .inside }
        if distance - fix.horizontalAccuracy > region.radiusMeters { return .outside }
        return .uncertain
    }

    /// The new satisfied set. Replaces membership for `fences` only; any other ID in
    /// `previous` is left as it was. A fix with unusable accuracy changes nothing.
    public static func satisfied(fences: [MonitoredFence], fix: LocationFix, previous: Set<UUID>) -> Set<UUID> {
        guard hasUsableAccuracy(fix) else { return previous }
        var next = previous
        for fence in fences {
            switch verdict(for: fence, fix: fix) {
            case .inside: next.insert(fence.id)
            case .outside: next.remove(fence.id)
            case .uncertain: break
            }
        }
        return next
    }
}

public enum FenceEvidence {
    /// Newest evidence wins. CLMonitor's record keeps its last verdict forever, so on a Mac
    /// where it never delivers it would otherwise undo every local check on the next reseed.
    /// A record with no date loses to any local verdict.
    public static func isSatisfied(monitorSatisfied: Bool, monitorDate: Date?, local: LocalFenceVerdict?) -> Bool {
        guard let local else { return monitorSatisfied }
        guard let monitorDate, monitorDate > local.date else { return local.inside }
        return monitorSatisfied
    }
}
