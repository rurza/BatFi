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
