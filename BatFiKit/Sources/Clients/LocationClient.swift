//
//  LocationClient.swift
//  BatFi
//
//  Abstraction over CoreLocation for the automation feature, split into two surfaces with
//  deliberately different lifetimes:
//
//  - `snapshotUpdates` drives the location picker and permission UI. It runs continuous
//    CoreLocation updates, but only while a consumer is iterating — i.e. while the picker
//    sheet is open.
//  - `setMonitoredFences` / `fenceStates` drive rule evaluation via CLMonitor. CoreLocation
//    evaluates the geofences and reports satisfied/unsatisfied; no continuous updates run.
//    `checkFences` backs it up with an occasional one-shot fix decided locally.
//

import AppShared
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct LocationClient: Sendable {
    /// Current snapshot, then every change. Yields the current value immediately on subscribe.
    /// While at least one consumer iterates, CoreLocation updates run. Picker/permission UI only.
    public var snapshotUpdates: @Sendable () -> AsyncStream<LocationSnapshot> = { AsyncStream { _ in } }

    /// Reconcile the monitored set. Passing `[]` removes every condition and stops all
    /// monitoring. Idempotent: fences whose centre and monitored radius are unchanged are left
    /// alone, preserving their resolved state.
    public var setMonitoredFences: @Sendable ([MonitoredFence]) async -> Void

    /// Satisfied fence IDs: the current set immediately, then every change. Backed by
    /// CLMonitor; starts no continuous location updates.
    public var fenceStates: @Sendable () -> AsyncStream<Set<UUID>> = { AsyncStream { _ in } }

    /// Take one location fix and decide every monitored fence locally, for Macs where CLMonitor
    /// never delivers. Returns at once; the check runs in the background, at most one at a time,
    /// and does nothing unless authorized with fences monitored. Updates stop when it ends.
    public var checkFences: @Sendable (FenceCheckReason) async -> Void

    /// Prompt for authorization. No-op unless `.notDetermined`.
    public var requestAuthorization: @Sendable () -> Void
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
