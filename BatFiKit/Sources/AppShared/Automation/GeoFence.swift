//
//  GeoFence.swift
//  BatFi
//
//  Part of the calendar/automation feature. Pure value types with no CoreLocation
//  dependency so the matching logic stays trivially testable.
//

import Foundation

/// A latitude/longitude pair. Kept independent of CoreLocation so the model and its
/// resolution logic can be unit-tested without importing a system framework.
public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance to another coordinate, in meters (haversine).
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0 // meters
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

/// A circular geographic region: a named center plus a radius.
public struct GeoFence: Codable, Equatable, Sendable {
    public var center: Coordinate
    public var radiusMeters: Double
    public var label: String

    public init(center: Coordinate, radiusMeters: Double, label: String) {
        self.center = center
        self.radiusMeters = radiusMeters
        self.label = label
    }

    /// Whether `coordinate` falls inside this fence.
    public func contains(_ coordinate: Coordinate) -> Bool {
        center.distance(to: coordinate) <= radiusMeters
    }
}

public extension GeoFence {
    /// Smallest radius CoreLocation can monitor meaningfully. The location manager requests
    /// `kCLLocationAccuracyHundredMeters`, so anything tighter cannot behave as labelled.
    static let minimumMonitoredRadiusMeters: Double = 100

    /// Radius actually submitted to CoreLocation. Never below the accuracy floor.
    ///
    /// Clamping lives here, not at the CoreLocation boundary, so that the value used to build
    /// a condition and the value used to compare against an existing condition are the same.
    /// Clamping only on the way in would make every reconciliation pass see a difference and
    /// churn the condition, resetting its monitoring state.
    var monitoredRadiusMeters: Double { max(radiusMeters, Self.minimumMonitoredRadiusMeters) }
}

/// Centre and radius alone. `CLMonitor` persists no label, so a condition read back from it
/// cannot reconstruct a `GeoFence`; this is what both sides of a comparison reduce to.
public struct MonitoredRegion: Sendable, Equatable {
    public var center: Coordinate
    public var radiusMeters: Double

    public init(center: Coordinate, radiusMeters: Double) {
        self.center = center
        self.radiusMeters = radiusMeters
    }

    /// Equality within the tolerance of a round trip through CoreLocation's persisted store.
    /// Exact `Double` equality would churn conditions on every launch.
    public func matches(_ other: MonitoredRegion) -> Bool {
        abs(center.latitude - other.center.latitude) < 1e-6
            && abs(center.longitude - other.center.longitude) < 1e-6
            && abs(radiusMeters - other.radiusMeters) < 0.5
    }
}

/// A geofence submitted for monitoring, identified by the rule that owns it.
public struct MonitoredFence: Sendable, Equatable, Identifiable {
    public var id: UUID          // == AutomationRule.id
    public var fence: GeoFence

    public init(id: UUID, fence: GeoFence) {
        self.id = id
        self.fence = fence
    }

    /// The part CoreLocation actually stores, and the only part reconciliation compares.
    public var region: MonitoredRegion {
        MonitoredRegion(center: fence.center, radiusMeters: fence.monitoredRadiusMeters)
    }
}
