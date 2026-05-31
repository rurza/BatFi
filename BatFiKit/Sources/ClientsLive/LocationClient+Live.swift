//
//  LocationClient+Live.swift
//  BatFi
//
//  CoreLocation-backed implementation. CLLocationManager is created and used exclusively on
//  the main run loop — Apple requires the manager to live on a thread with an active run
//  loop, otherwise the authorization prompt may not appear and delegate callbacks never
//  fire. The synchronously-readable authorization snapshot is guarded by a lock.
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

private final class LocationCoordinator: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let logger = Logger(category: "LocationClient")
    private let lock = NSLock()

    /// Created lazily, always on the main thread (see `manager()`), so its delegate callbacks
    /// are delivered on the main run loop. Only touched on the main thread.
    private var _manager: CLLocationManager?

    // Guarded by `lock`.
    private var authorization: LocationAuthorization = .notDetermined
    private var oneShotContinuations: [CheckedContinuation<Coordinate?, Never>] = []
    private var streamContinuations: [UUID: AsyncStream<Coordinate>.Continuation] = [:]
    private var isUpdating = false
    private var wantsOneShotAfterAuthorization = false

    override init() {
        super.init()
        // Warm up the manager on main so we have an authorization snapshot early.
        onMain { [self] in _ = manager() }
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
                manager.requestAlwaysAuthorization()
            }
        }
    }

    func oneShotCoordinate() async -> Coordinate? {
        await withCheckedContinuation { continuation in
            onMain { [self] in
                let manager = manager()
                lock.withLock { oneShotContinuations.append(continuation) }
                switch manager.authorizationStatus {
                case .authorizedAlways:
                    manager.requestLocation()
                case .notDetermined:
                    lock.withLock { wantsOneShotAfterAuthorization = true }
                    manager.requestAlwaysAuthorization()
                default: // denied / restricted
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
                startUpdatingIfNeeded()
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                onMain { [self] in
                    let remaining = lock.withLock { () -> Int in
                        streamContinuations[id] = nil
                        return streamContinuations.count
                    }
                    if remaining == 0 { stopUpdating() }
                }
            }
        }
    }

    // MARK: - CLLocationManagerDelegate (delivered on main)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let mapped = Self.map(manager.authorizationStatus)
        store(authorization: mapped)
        switch mapped {
        case .authorized:
            let wantsOneShot = lock.withLock { () -> Bool in
                let value = wantsOneShotAfterAuthorization
                wantsOneShotAfterAuthorization = false
                return value
            }
            if wantsOneShot { manager.requestLocation() }
            startUpdatingIfNeeded()
        case .denied:
            lock.withLock { wantsOneShotAfterAuthorization = false }
            resolveOneShots(with: nil)
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
        resolveOneShots(with: coordinate)
        let streams = lock.withLock { Array(streamContinuations.values) }
        for stream in streams { stream.yield(coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.warning("Location update failed: \(error.localizedDescription, privacy: .public)")
        resolveOneShots(with: nil)
    }

    // MARK: - Helpers (main thread)

    private func startUpdatingIfNeeded() {
        let hasSubscribers = lock.withLock { !streamContinuations.isEmpty }
        guard hasSubscribers, !isUpdating else { return }
        let manager = manager()
        guard manager.authorizationStatus == .authorizedAlways else {
            if manager.authorizationStatus == .notDetermined {
                manager.requestAlwaysAuthorization()
            }
            return
        }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    private func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        _manager?.stopUpdatingLocation()
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
