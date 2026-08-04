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
        // `SnapshotCoordinator` receives `locationManagerDidChangeAuthorization` whether or not
        // any snapshot consumer exists, so it is the process's single source of authorization
        // truth. The fence half needs it as well, and cannot observe CoreLocation itself: it
        // owns no `CLLocationManager`. Without this wiring the first-run grant — which lands
        // seconds *after* `setMonitoredFences` has already added the conditions — would never
        // reconcile, and a later revocation would leave `CLMonitor`'s persisted `.satisfied`
        // driving a rule the app can no longer track.
        Task { @MainActor in
            SnapshotCoordinator.shared.observeAuthorization { authorization in
                Task { await fences.setAuthorization(authorization) }
            }
        }
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
    private var authorizationObserver: (@Sendable (LocationAuthorization) -> Void)?

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
                // Registration and `onTermination`'s removal are two unstructured tasks on the
                // main actor's priority-ordered queue and can run in either order. Registering
                // unconditionally would let a removal that ran first be undone by this task,
                // leaving a dead continuation in the dictionary — `reconcileUpdating` would then
                // hold `startUpdatingLocation` on forever with no picker open, which is the exact
                // drain this branch exists to remove. The initial yield's result is the only
                // reliable signal that the stream is already gone, so it decides whether to
                // register at all.
                if case .terminated = continuation.yield(coordinator.snapshot) {
                    coordinator.continuations[id] = nil
                } else {
                    coordinator.continuations[id] = continuation
                    // Toggling the system-wide Location Services switch does not change this
                    // app's authorization, so no delegate callback fires and the cached value can
                    // be a stale `true`. Subscribing is the moment the picker is about to render
                    // the `.servicesOff` banner, so re-read it here.
                    coordinator.refreshServicesEnabled()
                }
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

    /// Registers `handler` and delivers the current value immediately. The immediate delivery is
    /// load-bearing: on a launch where access was already granted, `CLLocationManager` reports no
    /// authorization *change*, so a handler that only saw subsequent callbacks would never learn
    /// it is authorized.
    func observeAuthorization(_ handler: @escaping @Sendable (LocationAuthorization) -> Void) {
        authorizationObserver = handler
        handler(snapshot.authorization)
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
            self.authorizationObserver?(mapped)
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
    private var isReconciling = false
    private var reconcilePending = false
    private var authorization: LocationAuthorization = .notDetermined
    /// Whether `setFences` has ever run. Distinguishes "nothing is desired" from "nothing has
    /// been submitted yet", which are the same `desired == []` but must reconcile differently.
    private var hasReceivedDesiredSet = false

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
        // Registration and removal are separate tasks hopping onto this actor and may arrive in
        // either order. Yielding first and registering only if the stream is still live keeps a
        // dead continuation from being re-inserted after `removeContinuation` already ran, which
        // would grow `continuations` for the life of the process.
        if case .terminated = continuation.yield(satisfied) {
            continuations[id] = nil
            return
        }
        continuations[id] = continuation
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    func setFences(_ fences: [MonitoredFence]) async {
        desired = fences
        hasReceivedDesiredSet = true
        await reconcile()
    }

    /// Fence monitoring's only view of authorization. `CLMonitor` requires `authorizedAlways` and
    /// persists each condition's last event across launches, so this actor cannot treat an
    /// unauthorized monitor as failing closed on its own — the persisted `.satisfied` outlives
    /// the grant that produced it.
    ///
    /// `desired` is deliberately retained through denial, so a later grant re-applies it without
    /// the user having to edit a rule.
    func setAuthorization(_ newValue: LocationAuthorization) async {
        guard newValue != authorization else { return }
        authorization = newValue
        logger.notice("Fence authorization: \(String(describing: newValue), privacy: .public)")

        switch newValue {
        case .authorized:
            // The first-run path: `AutomationManager` calls `requestAuthorization()` and then
            // immediately awaits `setMonitoredFences`, so conditions are added with
            // `assuming: .unknown` while the prompt is still on screen. Nothing else re-runs when
            // the user clicks Allow, so without this the fence could stay `.unknown` until the
            // next rule edit or relaunch.
            //
            // Reconciling before anything has been submitted would be actively harmful: the plan
            // would be computed against an empty `desired` and would remove the persisted
            // conditions before `AutomationManager` submits them, throwing away exactly the
            // cold-start state CLMonitor kept. The first `setFences` reconciles with the
            // authorization already stored, so nothing is lost by waiting.
            guard hasReceivedDesiredSet else { return }
            // Routed through the serialised wrapper, not `performReconcile`, so this cannot
            // interleave with an in-flight `setFences` and re-add a condition CoreLocation has
            // already resolved.
            await reconcile()
        case .denied, .restricted, .notDetermined:
            // Stop geofenced rules from matching rather than holding a verdict the app can no
            // longer verify.
            publish([])
        }
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

    /// Serialises reconciliation against itself. `setMonitoredFences` is public and `async`, and
    /// `performReconcile` suspends at every `CLMonitor` call, so two overlapping calls would
    /// otherwise interleave: the first builds `current` from the pre-existing store, suspends,
    /// and resumes to evaluate a plan against a fresh `desired` but a stale `current` — re-adding
    /// a condition the second call already added, with `assuming: .unknown`, discarding state
    /// CoreLocation had resolved and flickering the rule off.
    ///
    /// Overlapping runs coalesce into a single trailing pass, which recomputes `current` from
    /// scratch. That is the point: the pending run must never reuse a snapshot taken earlier.
    private func reconcile() async {
        if isReconciling {
            reconcilePending = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }
        repeat {
            reconcilePending = false
            await performReconcile()
        } while reconcilePending
    }

    private func performReconcile() async {
        let monitor = await monitorIfNeeded()

        var current: [UUID: MonitoredRegion] = [:]
        var unreducible: [String] = []
        for identifier in await monitor.identifiers {
            guard let id = UUID(uuidString: identifier),
                  let record = await monitor.record(for: identifier),
                  let condition = record.condition as? CLMonitor.CircularGeographicCondition
            else {
                // An identifier that cannot be reduced to a `MonitoredRegion` never enters
                // `current`, and `plan` derives removals only from `current.keys` — so left here
                // it would be invisible to reconciliation forever, including when `desired` is
                // empty. locationd would keep evaluating a condition in
                // `~/Library/CoreLocation/<BundleID>/BatFiAutomation.monitor` for the life of the
                // install, falsifying the documented contract that passing `[]` stops all
                // monitoring. Tracked separately and removed below.
                unreducible.append(identifier)
                continue
            }
            current[id] = MonitoredRegion(
                center: Coordinate(
                    latitude: condition.center.latitude,
                    longitude: condition.center.longitude
                ),
                radiusMeters: condition.radius
            )
        }

        // A transient nil `record(for:)` on a fence that is still wanted must not delete it; only
        // identifiers the desired set does not claim are orphans. One that *is* claimed is simply
        // absent from `current`, so the plan re-adds it.
        let desiredIdentifiers = Set(desired.map(\.id.uuidString))
        let orphans = unreducible.filter { !desiredIdentifiers.contains($0) }

        let plan = FenceReconciliation.plan(desired: desired, current: current)
        if !plan.isEmpty || !orphans.isEmpty {
            logger.notice(
                "Reconciling fences. remove=\(plan.toRemove.count) add=\(plan.toAdd.count) orphans=\(orphans.count)"
            )
        }
        for id in plan.toRemove {
            await monitor.remove(id.uuidString)
        }
        for identifier in orphans {
            await monitor.remove(identifier)
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
        // ...which is precisely why this must be gated. A persisted `.satisfied` outlives the
        // authorization that produced it: revoke access while inside "Home" and the next launch
        // would read `.satisfied` straight back off disk and keep the rule active with no
        // location capability at all. Fail closed until authorization is known to be granted.
        guard authorization == .authorized else {
            publish([])
            return
        }

        var next: Set<UUID> = []
        for fence in desired {
            let state = await monitor.record(for: fence.id.uuidString)?.lastEvent.state
            // .unknown and .unmonitored fail closed, matching the old nil-coordinate semantics.
            if state == .satisfied { next.insert(fence.id) }
        }
        publish(next)
    }

    private static let minimumRestartDelay: Duration = .seconds(5)
    private static let maximumRestartDelay: Duration = .seconds(60)

    /// Retries forever, because a stream that ends or throws must not leave fence events dead
    /// for the rest of the process lifetime — automation would silently stop responding to
    /// location with nothing but a log line to show for it.
    ///
    /// The only exits are cancellation and an empty desired set. Both are already driven by
    /// `reconcile()`, which cancels and nils `eventTask` itself; this task deliberately never
    /// assigns `eventTask` from inside its own body, since `reconcile()` may have just stored
    /// a newer task and self-nilling could null out the wrong one.
    private func consumeEvents() async {
        var restartDelay = Self.minimumRestartDelay
        var lastReason: String?

        while !Task.isCancelled, !desired.isEmpty {
            guard let monitor else { return }
            var deliveredEvent = false
            let reason: String
            do {
                for try await event in await monitor.events {
                    guard let id = UUID(uuidString: event.identifier) else { continue }
                    deliveredEvent = true
                    var next = satisfied
                    if event.state == .satisfied { next.insert(id) } else { next.remove(id) }
                    logger.notice("Fence event. state=\(String(describing: event.state), privacy: .public)")
                    publish(next)
                }
                reason = "stream ended"
            } catch {
                reason = "stream failed: \(error.localizedDescription)"
            }

            // A stream that did deliver before ending was interrupted, not wedged, so the next
            // backoff starts from the floor again.
            if deliveredEvent {
                restartDelay = Self.minimumRestartDelay
                lastReason = nil
            }

            // A permanently wedged stream must not write a warning to disk every cycle. The
            // first failure — and any change of failure — is a warning; identical repeats drop
            // to debug, which is not persisted.
            let seconds = restartDelay.components.seconds
            if reason != lastReason {
                logger.warning("Fence event \(reason, privacy: .public); restarting in \(seconds, privacy: .public)s")
                lastReason = reason
            } else {
                logger.debug("Fence event \(reason, privacy: .public); restarting in \(seconds, privacy: .public)s")
            }

            // Transitions may have been missed while the stream was down, so re-read the
            // authoritative per-condition state before resuming.
            await reseedSatisfied(from: monitor)

            // Hot-loop guard. A fixed cadence would be a permanent 12-wakeups-per-minute floor
            // in the exact app whose point here is removing a background wakeup, so it backs
            // off to a one-minute ceiling while the stream stays wedged.
            try? await Task.sleep(for: restartDelay)
            restartDelay = min(restartDelay * 2, Self.maximumRestartDelay)
        }
    }

    private func publish(_ next: Set<UUID>) {
        guard next != satisfied else { return }
        satisfied = next
        for continuation in continuations.values { continuation.yield(next) }
    }
}
