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
}
