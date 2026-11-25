//
//  LocalFenceCheckTests.swift
//  BatFi
//
//  Unit tests for deciding fence membership from a one-shot fix, the fallback for Macs where
//  CLMonitor never delivers an event.
//

import Foundation
import Testing

@testable import AppShared

private let office = Coordinate(latitude: 52.2297, longitude: 21.0122)
private let requestedAt = Date(timeIntervalSince1970: 1_800_000_000)

/// A coordinate `meters` due north of `office`.
private func north(_ meters: Double) -> Coordinate {
    Coordinate(latitude: office.latitude + meters / 111_195, longitude: office.longitude)
}

private func fix(
    _ coordinate: Coordinate,
    accuracy: Double = 50,
    at timestamp: Date = requestedAt.addingTimeInterval(5)
) -> LocationFix {
    LocationFix(coordinate: coordinate, horizontalAccuracy: accuracy, timestamp: timestamp)
}

private func monitored(_ radius: Double = 400, id: UUID = UUID()) -> MonitoredFence {
    MonitoredFence(id: id, fence: GeoFence(center: office, radiusMeters: radius))
}

@Suite struct LocalFenceVerdictTests {
    @Test func insideRadiusIsInside() {
        #expect(LocalFenceCheck.verdict(for: monitored(), fix: fix(north(390))) == .inside)
    }

    @Test func insideEvenWithPoorAccuracy() {
        // The fix's best estimate is inside; accuracy only widens the band in which the
        // previous state is kept, on the outside edge.
        #expect(LocalFenceCheck.verdict(for: monitored(), fix: fix(north(300), accuracy: 900)) == .inside)
    }

    @Test func clearlyOutsideIsOutside() {
        #expect(LocalFenceCheck.verdict(for: monitored(), fix: fix(north(9_000))) == .outside)
    }

    @Test func outsideButWithinAccuracyIsUncertain() {
        // 450 m from the centre, 400 m radius, ±65 m: could be inside.
        #expect(LocalFenceCheck.verdict(for: monitored(), fix: fix(north(450), accuracy: 65)) == .uncertain)
    }

    @Test func outsideBeyondAccuracyIsOutside() {
        #expect(LocalFenceCheck.verdict(for: monitored(), fix: fix(north(480), accuracy: 65)) == .outside)
    }

    @Test func usesTheMonitoredRadiusFloor() {
        // A legacy 50 m fence is monitored as 100 m; the local check must agree with CLMonitor.
        #expect(LocalFenceCheck.verdict(for: monitored(50), fix: fix(north(90), accuracy: 10)) == .inside)
    }
}

@Suite struct LocalFenceUsabilityTests {
    @Test func freshAccurateFixIsUsable() {
        #expect(LocalFenceCheck.isUsable(fix(north(0)), requestedAt: requestedAt))
    }

    @Test func fixFromBeforeTheRequestIsNotUsable() {
        // CoreLocation hands back its cached location first; that is not evidence of where the
        // Mac is now.
        let stale = fix(north(0), at: requestedAt.addingTimeInterval(-1))
        #expect(!LocalFenceCheck.isUsable(stale, requestedAt: requestedAt))
    }

    @Test func absurdAccuracyIsNotUsable() {
        #expect(!LocalFenceCheck.isUsable(fix(north(0), accuracy: 1_001), requestedAt: requestedAt))
        #expect(LocalFenceCheck.isUsable(fix(north(0), accuracy: 1_000), requestedAt: requestedAt))
    }

    @Test func negativeOrNonFiniteAccuracyIsNotUsable() {
        // CoreLocation reports a negative accuracy for an invalid coordinate.
        #expect(!LocalFenceCheck.isUsable(fix(north(0), accuracy: -1), requestedAt: requestedAt))
        #expect(!LocalFenceCheck.isUsable(fix(north(0), accuracy: .nan), requestedAt: requestedAt))
        #expect(!LocalFenceCheck.isUsable(fix(north(0), accuracy: .infinity), requestedAt: requestedAt))
    }
}

@Suite struct LocalFenceSatisfiedSetTests {
    @Test func entersAndLeaves() {
        let office = monitored()
        let entered = LocalFenceCheck.satisfied(fences: [office], fix: fix(north(10)), previous: [])
        #expect(entered == [office.id])
        let left = LocalFenceCheck.satisfied(fences: [office], fix: fix(north(9_000)), previous: entered)
        #expect(left == [])
    }

    @Test func uncertainKeepsPreviousState() {
        let office = monitored()
        let edge = fix(north(450), accuracy: 65)
        #expect(LocalFenceCheck.satisfied(fences: [office], fix: edge, previous: [office.id]) == [office.id])
        #expect(LocalFenceCheck.satisfied(fences: [office], fix: edge, previous: []) == [])
    }

    @Test func unusableAccuracyChangesNothing() {
        let office = monitored()
        let coarse = fix(north(9_000), accuracy: 5_000)
        #expect(LocalFenceCheck.satisfied(fences: [office], fix: coarse, previous: [office.id]) == [office.id])
    }

    @Test func fencesNotEvaluatedKeepTheirState() {
        let office = monitored()
        let other = UUID()
        let result = LocalFenceCheck.satisfied(fences: [office], fix: fix(north(9_000)), previous: [office.id, other])
        #expect(result == [other])
    }

    @Test func evaluatesEachFenceIndependently() {
        let office = monitored()
        let home = MonitoredFence(
            id: UUID(),
            fence: GeoFence(center: north(9_000), radiusMeters: 400)
        )
        let result = LocalFenceCheck.satisfied(fences: [office, home], fix: fix(north(9_050)), previous: [office.id])
        #expect(result == [home.id])
    }
}

@Suite struct FenceEvidenceTests {
    private let earlier = Date(timeIntervalSince1970: 1_800_000_000)
    private var later: Date { earlier.addingTimeInterval(60) }

    @Test func monitorAloneDecidesWithoutALocalVerdict() {
        #expect(FenceEvidence.isSatisfied(monitorSatisfied: true, monitorDate: earlier, local: nil))
        #expect(!FenceEvidence.isSatisfied(monitorSatisfied: false, monitorDate: earlier, local: nil))
    }

    @Test func newerLocalVerdictWins() {
        // The field case: CLMonitor's record is stuck at whatever it last said, while the
        // Mac has moved and a local check has seen it.
        let local = LocalFenceVerdict(inside: true, date: later)
        #expect(FenceEvidence.isSatisfied(monitorSatisfied: false, monitorDate: earlier, local: local))
    }

    @Test func newerMonitorEventWins() {
        let local = LocalFenceVerdict(inside: true, date: earlier)
        #expect(!FenceEvidence.isSatisfied(monitorSatisfied: false, monitorDate: later, local: local))
    }

    @Test func localVerdictWinsOverAnUndatedRecord() {
        let local = LocalFenceVerdict(inside: true, date: earlier)
        #expect(FenceEvidence.isSatisfied(monitorSatisfied: false, monitorDate: nil, local: local))
    }
}
