//
//  LocationClient.swift
//  BatFi
//
//  Abstraction over CoreLocation for the calendar/automation feature. Vends the current
//  coordinate (one-shot) and a stream of updates for geofence evaluation.
//

import AppShared
import Dependencies
import DependenciesMacros
import Foundation

/// Authorization state, decoupled from `CLAuthorizationStatus` so callers needn't import
/// CoreLocation.
public enum LocationAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

@DependencyClient
public struct LocationClient: Sendable {
    /// Current authorization status.
    public var authorizationStatus: @Sendable () -> LocationAuthorization = { .notDetermined }
    /// Ask the user for permission (no-op if already determined).
    public var requestAuthorization: @Sendable () -> Void
    /// One-shot best-effort current coordinate. Returns nil when unavailable or denied.
    public var currentCoordinate: @Sendable () async -> Coordinate?
    /// Continuous coordinate updates while at least one consumer is iterating. Starts and
    /// stops the underlying location updates based on demand.
    public var coordinateUpdates: @Sendable () -> AsyncStream<Coordinate> = { AsyncStream { _ in } }
}

extension LocationClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: LocationClient = .init()
}

public extension DependencyValues {
    var locationClient: LocationClient {
        get { self[LocationClient.self] }
        set { self[LocationClient.self] = newValue }
    }
}
