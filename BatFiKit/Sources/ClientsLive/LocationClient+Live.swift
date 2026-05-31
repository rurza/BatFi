//
//  LocationClient+Live.swift
//  BatFi
//
//  CoreLocation-backed implementation. All CLLocationManager interaction happens on the
//  main run loop (CoreLocation requires an active run loop); the synchronously-readable
//  authorization snapshot is guarded by a lock.
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
    private let manager = CLLocationManager()

    // Guarded by `lock`.
    private var authorization: LocationAuthorization = .notDetermined
    private var oneShotContinuations: [CheckedContinuation<Coordinate?, Never>] = []
    private var streamContinuations: [UUID: AsyncStream<Coordinate>.Continuation] = [:]
    private var isUpdating = false

    override init() {
        super.init()
        onMain { [self] in
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            store(authorization: Self.map(manager.authorizationStatus))
        }
    }

    // MARK: - Public surface

    func currentAuthorization() -> LocationAuthorization {
        lock.withLock { authorization }
    }

    func requestAuthorization() {
        onMain { [self] in
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
        }
    }

    func oneShotCoordinate() async -> Coordinate? {
        await withCheckedContinuation { continuation in
            onMain { [self] in
                lock.withLock { oneShotContinuations.append(continuation) }
                if manager.authorizationStatus == .notDetermined {
                    manager.requestWhenInUseAuthorization()
                }
                manager.requestLocation()
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

    // MARK: - CLLocationManagerDelegate (called on main)

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let mapped = Self.map(manager.authorizationStatus)
        store(authorization: mapped)
        if mapped == .authorized {
            startUpdatingIfNeeded()
        } else if mapped == .denied {
            // Fail any pending one-shot requests rather than hanging.
            resolveOneShots(with: nil)
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

    // MARK: - Helpers

    private func startUpdatingIfNeeded() {
        let hasSubscribers = lock.withLock { !streamContinuations.isEmpty }
        guard hasSubscribers, !isUpdating else { return }
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization()
            }
            return
        }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    private func stopUpdating() {
        guard isUpdating else { return }
        isUpdating = false
        manager.stopUpdatingLocation()
    }

    private func resolveOneShots(with coordinate: Coordinate?) {
        let pending = lock.withLock { () -> [CheckedContinuation<Coordinate?, Never>] in
            let conts = oneShotContinuations
            oneShotContinuations.removeAll()
            return conts
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
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .denied
        }
    }
}
