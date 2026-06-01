//
//  LocationClient+Live.swift
//  BatFi
//
//  CoreLocation-backed implementation. CLLocationManager is created and used exclusively on
//  the main run loop (Apple requires the manager to live on a thread with an active run
//  loop, otherwise the authorization prompt may not appear and delegate callbacks never
//  fire). The synchronously-readable authorization snapshot is guarded by a lock.
//
//  One-shot requests use `startUpdatingLocation` (which keeps trying until a fix arrives)
//  with a hard timeout, rather than `requestLocation` (which gives up almost immediately on
//  Macs that rely on Wi-Fi positioning). Every step is logged so failures are diagnosable.
//

import AppShared
import Clients
import CoreLocation
import Dependencies
import Foundation
import os

extension LocationClient: DependencyKey {
    public static let liveValue: LocationClient = {
        let coordinator = LocationCoordinator()
        return LocationClient(
            authorizationStatus: { coordinator.currentAuthorization() },
            requestAuthorization: { coordinator.requestAuthorization() },
            currentCoordinate: { await coordinator.oneShotCoordinate() },
            coordinateUpdates: { coordinator.makeUpdatesStream() }
        )
    }()
}

private let oneShotTimeout: TimeInterval = 12

private final class LocationCoordinator: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let logger = Logger(category: "LocationClient")
    private let lock = NSLock()

    /// Created lazily, always on the main thread (see `manager()`), so delegate callbacks are
    /// delivered on the main run loop. Only touched on the main thread.
    private var _manager: CLLocationManager?

    // Guarded by `lock`.
    private var authorization: LocationAuthorization = .notDetermined
    private var oneShotContinuations: [CheckedContinuation<Coordinate?, Never>] = []
    private var streamContinuations: [UUID: AsyncStream<Coordinate>.Continuation] = [:]
    private var wantsOneShotAfterAuthorization = false

    // Main-thread only.
    private var oneShotActive = false
    private var isUpdating = false

    override init() {
        super.init()
        onMain { [self] in
            let manager = manager()
            logger.notice("LocationClient initialized. auth=\(self.describe(manager.authorizationStatus), privacy: .public)")
        }
    }

    /// Returns the manager, creating it on first use. MUST be called on the main thread.
    private func manager() -> CLLocationManager {
        if let _manager { return _manager }
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        _manager = manager
        store(authorization: Self.map(manager.authorizationStatus))
        return manager
    }

    // MARK: - Public surface

    func currentAuthorization() -> LocationAuthorization {
        lock.withLock { authorization }
    }

    func requestAuthorization() {
        onMain { [self] in
            let manager = manager()
            if manager.authorizationStatus == .notDetermined {
                logger.notice("Requesting location authorization")
                manager.requestAlwaysAuthorization()
            }
        }
    }

    func oneShotCoordinate() async -> Coordinate? {
        await withCheckedContinuation { continuation in
            onMain { [self] in
                let manager = manager()
                lock.withLock { oneShotContinuations.append(continuation) }
                logger.notice("One-shot location requested. auth=\(self.describe(manager.authorizationStatus), privacy: .public)")
                switch manager.authorizationStatus {
                case .authorizedAlways:
                    oneShotActive = true
                    reconcileUpdating()
                    scheduleOneShotTimeout()
                case .notDetermined:
                    lock.withLock { wantsOneShotAfterAuthorization = true }
                    manager.requestAlwaysAuthorization()
                    scheduleOneShotTimeout()
                default:
                    logger.notice("Location not authorized; returning nil")
                    resolveOneShots(with: nil)
                }
            }
        }
    }

    func makeUpdatesStream() -> AsyncStream<Coordinate> {
        let id = UUID()
        return AsyncStream { continuation in
            onMain { [self] in
                lock.withLock { streamContinuations[id] = continuation }
                reconcileUpdating()
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                onMain { [self] in
                    lock.withLock { _ = streamContinuations.removeValue(forKey: id) }
                    reconcileUpdating()
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (delivered on main)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let mapped = Self.map(manager.authorizationStatus)
        store(authorization: mapped)
        logger.notice("Authorization changed: \(self.describe(manager.authorizationStatus), privacy: .public)")
        switch mapped {
        case .authorized:
            let wantsOneShot = lock.withLock { () -> Bool in
                let value = wantsOneShotAfterAuthorization
                wantsOneShotAfterAuthorization = false
                return value
            }
            if wantsOneShot { oneShotActive = true }
            reconcileUpdating()
        case .denied:
            lock.withLock { wantsOneShotAfterAuthorization = false }
            oneShotActive = false
            resolveOneShots(with: nil)
            reconcileUpdating()
        case .notDetermined:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        logger.notice("Received location \(coordinate.latitude, privacy: .public),\(coordinate.longitude, privacy: .public)")
        resolveOneShots(with: coordinate)
        oneShotActive = false
        let streams = lock.withLock { Array(streamContinuations.values) }
        for stream in streams { stream.yield(coordinate) }
        reconcileUpdating()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // With startUpdatingLocation, transient "location unknown" errors keep retrying, so
        // only a hard denial aborts the request; everything else waits for the timeout.
        logger.warning("Location error: \(error.localizedDescription, privacy: .public)")
        if (error as? CLError)?.code == .denied {
            oneShotActive = false
            resolveOneShots(with: nil)
            reconcileUpdating()
        }
    }

    // MARK: - Helpers (main thread)

    private func reconcileUpdating() {
        let needed = oneShotActive || lock.withLock { !streamContinuations.isEmpty }
        let manager = manager()
        if needed, !isUpdating {
            guard manager.authorizationStatus == .authorizedAlways else {
                if manager.authorizationStatus == .notDetermined {
                    manager.requestAlwaysAuthorization()
                }
                return
            }
            isUpdating = true
            logger.notice("Starting location updates")
            manager.startUpdatingLocation()
        } else if !needed, isUpdating {
            isUpdating = false
            logger.notice("Stopping location updates")
            manager.stopUpdatingLocation()
        }
    }

    private func scheduleOneShotTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + oneShotTimeout) { [weak self] in
            guard let self else { return }
            let stillPending = self.lock.withLock { !self.oneShotContinuations.isEmpty }
            guard stillPending else { return }
            self.logger.warning("One-shot location timed out after \(Int(oneShotTimeout))s")
            self.oneShotActive = false
            self.resolveOneShots(with: nil)
            self.reconcileUpdating()
        }
    }

    private func resolveOneShots(with coordinate: Coordinate?) {
        let pending = lock.withLock { () -> [CheckedContinuation<Coordinate?, Never>] in
            let continuations = oneShotContinuations
            oneShotContinuations.removeAll()
            return continuations
        }
        for continuation in pending { continuation.resume(returning: coordinate) }
    }

    private func store(authorization newValue: LocationAuthorization) {
        lock.withLock { authorization = newValue }
    }

    private func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "authorizedAlways"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    private func onMain(_ work: @escaping @Sendable () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted, .denied: return .denied
        case .authorizedAlways: return .authorized
        @unknown default: return .denied
        }
    }
}
