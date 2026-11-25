//
//  LocationSnapshot.swift
//  BatFi
//
//  Location state as the UI sees it. Pure value types with no CoreLocation dependency, so
//  the freshness and banner decisions are unit-testable. Rule evaluation consumes satisfied
//  fence IDs (see FenceReconciliation); only its fallback check reads a fix from here.
//

import Foundation

/// Authorization state, decoupled from `CLAuthorizationStatus` so callers needn't import
/// CoreLocation. `.restricted` is split out from `.denied` because an MDM-managed Mac cannot
/// be fixed by the user in System Settings and needs different copy.
public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case authorized
}

/// Everything the picker and permission UI need, in one broadcastable value.
public struct LocationSnapshot: Sendable, Equatable {
    public var authorization: LocationAuthorization
    /// System-wide Location Services switch, independent of this app's authorization.
    public var servicesEnabled: Bool
    public var lastFix: Coordinate?
    public var lastFixDate: Date?
    /// Horizontal accuracy of `lastFix` in meters, as CoreLocation reports it.
    public var lastFixAccuracy: Double?

    public init(
        authorization: LocationAuthorization = .notDetermined,
        servicesEnabled: Bool = true,
        lastFix: Coordinate? = nil,
        lastFixDate: Date? = nil,
        lastFixAccuracy: Double? = nil
    ) {
        self.authorization = authorization
        self.servicesEnabled = servicesEnabled
        self.lastFix = lastFix
        self.lastFixDate = lastFixDate
        self.lastFixAccuracy = lastFixAccuracy
    }

    /// The last fix in full, or `nil` while any part of it is unknown.
    public var fix: LocationFix? {
        guard let lastFix, let lastFixDate, let lastFixAccuracy else { return nil }
        return LocationFix(coordinate: lastFix, horizontalAccuracy: lastFixAccuracy, timestamp: lastFixDate)
    }

    /// Whether a usable fix exists that is younger than `interval`.
    public func hasFix(fresherThan interval: TimeInterval, now: Date = Date()) -> Bool {
        guard lastFix != nil, let lastFixDate else { return false }
        return now.timeIntervalSince(lastFixDate) < interval
    }
}

/// Which recovery banner the location picker shows. Extracted from the view so the mapping is
/// tested rather than buried in a view body.
public enum PermissionBannerState: Sendable, Equatable {
    case none
    case servicesOff
    case notDetermined
    case denied
    case restricted

    public init(_ snapshot: LocationSnapshot) {
        // Checked before authorization: when the system-wide switch is off, that is the
        // actionable problem regardless of what this app was granted.
        guard snapshot.servicesEnabled else { self = .servicesOff; return }
        switch snapshot.authorization {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .authorized: self = .none
        }
    }
}
