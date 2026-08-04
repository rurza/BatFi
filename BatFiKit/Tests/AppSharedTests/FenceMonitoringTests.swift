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

@Suite struct FenceReconciliationTests {
    private let idA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let idB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    @Test func emptyDesiredRemovesEverything() {
        let plan = FenceReconciliation.plan(
            desired: [],
            current: [idA: MonitoredRegion(center: warsaw, radiusMeters: 300)]
        )
        #expect(plan.toRemove == [idA])
        #expect(plan.toAdd.isEmpty)
    }

    @Test func newFenceIsAdded() {
        let desired = [MonitoredFence(id: idA, fence: fence(300))]
        let plan = FenceReconciliation.plan(desired: desired, current: [:])
        #expect(plan.toRemove.isEmpty)
        #expect(plan.toAdd.map(\.id) == [idA])
    }

    @Test func unchangedFenceProducesEmptyPlan() {
        // Load-bearing: re-adding resets CLMonitor state to .unknown and flickers the rule off.
        let desired = [MonitoredFence(id: idA, fence: fence(300))]
        let plan = FenceReconciliation.plan(
            desired: desired,
            current: [idA: MonitoredRegion(center: warsaw, radiusMeters: 300)]
        )
        #expect(plan.isEmpty)
    }

    @Test func subFloorFenceDoesNotChurn() {
        // A stored 50 m fence is monitored at 100 m. Both sides must compare as 100 m,
        // otherwise every pass would remove and re-add it.
        let desired = [MonitoredFence(id: idA, fence: fence(50))]
        let plan = FenceReconciliation.plan(
            desired: desired,
            current: [idA: MonitoredRegion(center: warsaw, radiusMeters: 100)]
        )
        #expect(plan.isEmpty)
    }

    @Test func changedRadiusReplaces() {
        let desired = [MonitoredFence(id: idA, fence: fence(500))]
        let plan = FenceReconciliation.plan(
            desired: desired,
            current: [idA: MonitoredRegion(center: warsaw, radiusMeters: 300)]
        )
        #expect(plan.toRemove == [idA])
        #expect(plan.toAdd.map(\.id) == [idA])
    }

    @Test func duplicateRuleIDsDoNotTrap() {
        // `desired` comes from rules decoded out of UserDefaults JSON, so a repeated ID is
        // reachable with a hand-edited or corrupted store. This used to be a `fatalError` inside
        // an actor. First entry wins, and the ID is submitted once.
        let desired = [
            MonitoredFence(id: idA, fence: fence(300)),
            MonitoredFence(id: idA, fence: fence(900, "Home copy")),
        ]
        let plan = FenceReconciliation.plan(desired: desired, current: [:])
        #expect(plan.toRemove.isEmpty)
        #expect(plan.toAdd.map(\.id) == [idA])
        #expect(plan.toAdd.first?.region.radiusMeters == 300)
    }

    @Test func duplicateRuleIDsDoNotChurnAnUnchangedFence() {
        // The duplicate must not make an otherwise-unchanged fence look changed and get
        // removed/re-added — that would reset its CLMonitor state to .unknown.
        let desired = [
            MonitoredFence(id: idA, fence: fence(300)),
            MonitoredFence(id: idA, fence: fence(900, "Home copy")),
        ]
        let plan = FenceReconciliation.plan(
            desired: desired,
            current: [idA: MonitoredRegion(center: warsaw, radiusMeters: 300)]
        )
        #expect(plan.isEmpty)
    }

    @Test func mixedAddRemoveAndKeep() {
        let desired = [
            MonitoredFence(id: idA, fence: fence(300)),   // unchanged → untouched
            MonitoredFence(id: idB, fence: fence(400)),   // new → added
        ]
        let plan = FenceReconciliation.plan(
            desired: desired,
            current: [
                idA: MonitoredRegion(center: warsaw, radiusMeters: 300),
                UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!:
                    MonitoredRegion(center: warsaw, radiusMeters: 900),  // gone → removed
            ]
        )
        #expect(plan.toAdd.map(\.id) == [idB])
        #expect(plan.toRemove.count == 1)
        #expect(plan.toRemove.first?.uuidString.hasPrefix("CCCCCCCC") == true)
    }
}
