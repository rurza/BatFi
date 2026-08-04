//
//  LocationClient+Live.swift
//  BatFi
//
//  CoreLocation-backed implementation, in two independent halves.
//
//  SnapshotCoordinator (@MainActor): drives the picker and permission UI. CLLocationManager
//  must live on a thread with an active run loop or the authorization prompt may not appear
//  and delegate callbacks never fire; @MainActor guarantees that structurally. Continuous
//  updates run only while at least one consumer iterates `snapshotUpdates()`, so closing the
//  picker stops them. `startUpdatingLocation` is used rather than `requestLocation` because
//  the latter gives up almost immediately on Macs relying on Wi-Fi positioning.
//
//  FenceMonitor (actor): drives rule evaluation via CLMonitor. CoreLocation evaluates the
//  geofences in locationd and reports satisfied/unsatisfied per condition, so this half runs
//  no continuous location updates and never receives a coordinate.
//

import AppShared
import Clients
import CoreLocation
import Dependencies
import Foundation
import os

extension LocationClient: DependencyKey {
    public static let liveValue: LocationClient = {
        let fences = FenceMonitor()
        return LocationClient(
            // `SnapshotCoordinator` is @MainActor, so it cannot be constructed here (this
            // initializer is nonisolated and synchronous). Its singleton is a `@MainActor
            // static let` reached from inside the main-actor hops below instead.
            snapshotUpdates: { SnapshotCoordinator.makeStream() },
            setMonitoredFences: { await fences.setFences($0) },
            fenceStates: { fences.makeStream() },
            requestAuthorization: { Task { @MainActor in SnapshotCoordinator.shared.requestAuthorization() } }
        )
    }()
}

// MARK: - Snapshot half

@MainActor
private final class SnapshotCoordinator: NSObject, CLLocationManagerDelegate {
    /// One instance for the process. Isolated to the main actor so `CLLocationManager` is
    /// always created and driven from the main run loop.
    static let shared = SnapshotCoordinator()

    private let logger = Logger(category: "LocationClient")
    private let manager = CLLocationManager()
    private var continuations: [UUID: AsyncStream<LocationSnapshot>.Continuation] = [:]
    private var snapshot = LocationSnapshot()
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        snapshot.authorization = Self.map(manager.authorizationStatus)
        // Seeding from the manager's own cached fix is what makes "Use current location"
        // instant in the common case, instead of racing locationd's push cadence.
        if let location = manager.location {
            snapshot.lastFix = Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
            snapshot.lastFixDate = location.timestamp
        }
        logger.notice("LocationClient initialized. auth=\(String(describing: self.snapshot.authorization), privacy: .public)")
        refreshServicesEnabled()
    }

    nonisolated static func makeStream() -> AsyncStream<LocationSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { @MainActor in
                let coordinator = SnapshotCoordinator.shared
                coordinator.continuations[id] = continuation
                continuation.yield(coordinator.snapshot)
                coordinator.reconcileUpdating()
            }
            continuation.onTermination = { _ in
                Task { @MainActor in
                    let coordinator = SnapshotCoordinator.shared
                    coordinator.continuations[id] = nil
                    coordinator.reconcileUpdating()
                }
            }
        }
    }

    func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        logger.notice("Requesting location authorization")
        manager.requestAlwaysAuthorization()
    }

    /// `CLLocationManager.locationServicesEnabled()` can block, so it is never called from
    /// view code. It is read off the main actor and published back. This means the value is
    /// optimistically `true` for the first moments after launch, which is acceptable: it
    /// drives a recovery hint and gates nothing.
    private func refreshServicesEnabled() {
        Task.detached(priority: .utility) {
            let enabled = CLLocationManager.locationServicesEnabled()
            await MainActor.run { self.update { $0.servicesEnabled = enabled } }
        }
    }

    private func update(_ mutate: (inout LocationSnapshot) -> Void) {
        var copy = snapshot
        mutate(&copy)
        guard copy != snapshot else { return }
        snapshot = copy
        for continuation in continuations.values { continuation.yield(copy) }
    }

    private func reconcileUpdating() {
        let wanted = !continuations.isEmpty && snapshot.authorization == .authorized
        if wanted, !isUpdating {
            isUpdating = true
            logger.notice("Starting location updates")
            manager.startUpdatingLocation()
        } else if !wanted, isUpdating {
            isUpdating = false
            logger.notice("Stopping location updates")
            manager.stopUpdatingLocation()
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let mapped = Self.map(manager.authorizationStatus)
        Task { @MainActor in
            self.logger.notice("Authorization changed: \(String(describing: mapped), privacy: .public)")
            self.update { $0.authorization = mapped }
            if mapped == .notDetermined, !self.continuations.isEmpty {
                self.manager.requestAlwaysAuthorization()
            }
            self.refreshServicesEnabled()
            self.reconcileUpdating()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let timestamp = location.timestamp
        Task { @MainActor in
            self.update {
                $0.lastFix = coordinate
                $0.lastFixDate = timestamp
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient "location unknown" errors keep retrying under startUpdatingLocation and
        // must not tear anything down. Only a hard denial changes state, and that arrives via
        // locationManagerDidChangeAuthorization anyway.
        Task { @MainActor in
            self.logger.warning("Location error: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways: return .authorized
        @unknown default: return .denied
        }
    }
}

// MARK: - Fence-monitoring half

private actor FenceMonitor {
    private let logger = Logger(category: "FenceMonitor")
    private var monitor: CLMonitor?
    private var desired: [MonitoredFence] = []
    private var satisfied: Set<UUID> = []
    private var continuations: [UUID: AsyncStream<Set<UUID>>.Continuation] = [:]
    private var eventTask: Task<Void, Never>?

    nonisolated func makeStream() -> AsyncStream<Set<UUID>> {
        let id = UUID()
        return AsyncStream { continuation in
            Task { await self.addContinuation(continuation, id: id) }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id) }
            }
        }
    }

    private func addContinuation(_ continuation: AsyncStream<Set<UUID>>.Continuation, id: UUID) {
        continuations[id] = continuation
        continuation.yield(satisfied)
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    func setFences(_ fences: [MonitoredFence]) async {
        desired = fences
        await reconcile()
    }

    private func monitorIfNeeded() async -> CLMonitor {
        if let monitor { return monitor }
        // Persists to ~/Library/CoreLocation/<BundleID>/BatFiAutomation.monitor. The app is
        // not sandboxed, so this is the real home directory. Only one CLMonitor per name may
        // be open at a time; LocationClient.liveValue is a singleton, which satisfies that.
        let created = await CLMonitor("BatFiAutomation")
        monitor = created
        return created
    }

    private func reconcile() async {
        let monitor = await monitorIfNeeded()

        var current: [UUID: MonitoredRegion] = [:]
        for identifier in await monitor.identifiers {
            guard let id = UUID(uuidString: identifier),
                  let record = await monitor.record(for: identifier),
                  let condition = record.condition as? CLMonitor.CircularGeographicCondition
            else { continue }
            current[id] = MonitoredRegion(
                center: Coordinate(
                    latitude: condition.center.latitude,
                    longitude: condition.center.longitude
                ),
                radiusMeters: condition.radius
            )
        }

        let plan = FenceReconciliation.plan(desired: desired, current: current)
        if !plan.isEmpty {
            logger.notice("Reconciling fences. remove=\(plan.toRemove.count) add=\(plan.toAdd.count)")
        }
        for id in plan.toRemove {
            await monitor.remove(id.uuidString)
        }
        for fence in plan.toAdd {
            // Both the submitted radius and the comparison above must reduce through the same
            // 100 m clamp, or every pass would remove and re-add the condition and reset its
            // state. `region` is that clamped form; `fence.fence.radiusMeters` is not.
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(
                    latitude: fence.region.center.latitude,
                    longitude: fence.region.center.longitude
                ),
                radius: fence.region.radiusMeters
            )
            await monitor.add(condition, identifier: fence.id.uuidString, assuming: .unknown)
        }

        await reseedSatisfied(from: monitor)

        if desired.isEmpty {
            eventTask?.cancel()
            eventTask = nil
        } else if eventTask == nil {
            eventTask = Task { [weak self] in await self?.consumeEvents() }
        }
    }

    /// CLMonitor persists each condition's last event across launches, so a Mac that was
    /// inside a fence when BatFi quit reports `.satisfied` immediately, with no new fix. This
    /// is why cold start is better here than it was with a cached coordinate.
    private func reseedSatisfied(from monitor: CLMonitor) async {
        var next: Set<UUID> = []
        for fence in desired {
            let state = await monitor.record(for: fence.id.uuidString)?.lastEvent.state
            // .unknown and .unmonitored fail closed, matching the old nil-coordinate semantics.
            if state == .satisfied { next.insert(fence.id) }
        }
        publish(next)
    }

    private func consumeEvents() async {
        guard let monitor else { return }
        do {
            for try await event in await monitor.events {
                guard let id = UUID(uuidString: event.identifier) else { continue }
                var next = satisfied
                if event.state == .satisfied { next.insert(id) } else { next.remove(id) }
                logger.notice("Fence event. state=\(String(describing: event.state), privacy: .public)")
                publish(next)
            }
        } catch {
            logger.warning("Fence event stream ended: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func publish(_ next: Set<UUID>) {
        guard next != satisfied else { return }
        satisfied = next
        for continuation in continuations.values { continuation.yield(next) }
    }
}
