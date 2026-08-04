//
//  FenceMonitoringTests.swift
//  BatFi
//
//  Unit tests for the pure geofence-monitoring logic: radius clamping, region
//  comparison, and the desired-vs-monitored reconciliation diff.
//

import Foundation
import Testing

@testable import AppShared

private let warsaw = Coordinate(latitude: 52.2297, longitude: 21.0122)

private func fence(_ radius: Double, _ label: String = "Home", at center: Coordinate = warsaw) -> GeoFence {
    GeoFence(center: center, radiusMeters: radius, label: label)
}

@Suite struct MonitoredRadiusTests {
    @Test func radiusBelowFloorIsClamped() {
        #expect(fence(50).monitoredRadiusMeters == 100)
    }

    @Test func radiusAtFloorIsUnchanged() {
        #expect(fence(100).monitoredRadiusMeters == 100)
    }

    @Test func radiusAboveFloorIsUnchanged() {
        #expect(fence(2000).monitoredRadiusMeters == 2000)
    }

    @Test func storedRadiusIsNotMutatedByClamping() {
        let f = fence(50)
        #expect(f.radiusMeters == 50)
        #expect(f.monitoredRadiusMeters == 100)
    }
}

@Suite struct MonitoredRegionTests {
    @Test func regionUsesClampedRadius() {
        let region = MonitoredFence(id: UUID(), fence: fence(50)).region
        #expect(region.radiusMeters == 100)
        #expect(region.center == warsaw)
    }

    @Test func identicalRegionsMatch() {
        let a = MonitoredRegion(center: warsaw, radiusMeters: 300)
        #expect(a.matches(MonitoredRegion(center: warsaw, radiusMeters: 300)))
    }

    @Test func roundTripJitterStillMatches() {
        // CLMonitor persists conditions to disk; values can come back with tiny drift.
        let a = MonitoredRegion(center: warsaw, radiusMeters: 300)
        let b = MonitoredRegion(
            center: Coordinate(latitude: 52.2297_000_4, longitude: 21.0122_000_4),
            radiusMeters: 300.2
        )
        #expect(a.matches(b))
    }

    @Test func movedCentreDoesNotMatch() {
        let a = MonitoredRegion(center: warsaw, radiusMeters: 300)
        let b = MonitoredRegion(center: Coordinate(latitude: 52.2400, longitude: 21.0122), radiusMeters: 300)
        #expect(!a.matches(b))
    }

    @Test func changedRadiusDoesNotMatch() {
        let a = MonitoredRegion(center: warsaw, radiusMeters: 300)
        #expect(!a.matches(MonitoredRegion(center: warsaw, radiusMeters: 350)))
    }

    @Test func subFloorFenceMatchesItsClampedReadBack() {
        // The property the AppShared-side clamp exists for: a stored 50 m fence and the 100 m
        // region CoreLocation reports back must compare equal, or reconciliation would remove
        // and re-add the condition on every pass and reset its monitoring state.
        let desired = MonitoredFence(id: UUID(), fence: fence(50)).region
        let readBack = MonitoredRegion(center: warsaw, radiusMeters: 100)
        #expect(desired.matches(readBack))
        #expect(readBack.matches(desired))
    }
}

@Suite struct LocationSnapshotTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(
        _ auth: LocationAuthorization = .authorized,
        servicesEnabled: Bool = true,
        fixAgeSeconds: TimeInterval? = nil
    ) -> LocationSnapshot {
        LocationSnapshot(
            authorization: auth,
            servicesEnabled: servicesEnabled,
            lastFix: fixAgeSeconds == nil ? nil : Coordinate(latitude: 52.2297, longitude: 21.0122),
            lastFixDate: fixAgeSeconds.map { now.addingTimeInterval(-$0) }
        )
    }

    @Test func freshFixIsFresh() {
        #expect(snapshot(fixAgeSeconds: 60).hasFix(fresherThan: 300, now: now))
    }

    @Test func staleFixIsNotFresh() {
        #expect(!snapshot(fixAgeSeconds: 600).hasFix(fresherThan: 300, now: now))
    }

    @Test func missingFixIsNotFresh() {
        #expect(!snapshot().hasFix(fresherThan: 300, now: now))
    }

    @Test func servicesOffWinsOverAuthorization() {
        // The system-wide switch is the actionable problem even when the app is authorized.
        #expect(PermissionBannerState(snapshot(.authorized, servicesEnabled: false)) == .servicesOff)
    }

    @Test func bannerMapsEachAuthorization() {
        #expect(PermissionBannerState(snapshot(.notDetermined)) == .notDetermined)
        #expect(PermissionBannerState(snapshot(.denied)) == .denied)
        #expect(PermissionBannerState(snapshot(.restricted)) == .restricted)
        #expect(PermissionBannerState(snapshot(.authorized)) == .none)
    }
}
