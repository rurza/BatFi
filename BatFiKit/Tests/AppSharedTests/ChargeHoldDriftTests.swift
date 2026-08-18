//
//  ChargeHoldDriftTests.swift
//  BatFi
//
//  The states below were measured on 26A5416b unless marked otherwise, because the whole
//  value of this check is that it does not fire on a healthy Mac. A drift warning on a Mac
//  that is working is worse than no warning at all: it teaches the user to ignore the one
//  that matters.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeHoldDriftTests {
    // MARK: - The fault, while it is happening

    @Test func chargingPastTheLimitIsDrift() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: true,
                batteryLevel: 74,
                limitInForce: 60,
                holdIsAttributed: nil
            )
        )
    }

    /// The limit is the boundary the mechanism is supposed to stop at, so current still
    /// going in *at* it is already the mechanism failing.
    @Test func chargingExactlyAtTheLimitIsDrift() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: true,
                batteryLevel: 60,
                limitInForce: 60,
                holdIsAttributed: nil
            )
        )
    }

    /// Below the limit charging is the point. Under `.firmwareRange` this is also the
    /// steady state — the band charges back up to the upper bound from the lower one.
    @Test func chargingBelowTheLimitIsNormal() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: true,
                batteryLevel: 59,
                limitInForce: 60,
                holdIsAttributed: nil
            ) == false
        )
    }

    // MARK: - The healthy states this must never call a fault

    /// Measured live: 74%, limit 60, `IsCharging` No, `Amperage` -1643 mA, `NotChargingReason`
    /// 16777216 (bit 24, the system charge limit). macOS draining to the limit is the
    /// mechanism working, and it sits above the limit for as long as the drain takes.
    @Test func aSystemDrainTowardTheLimitIsNotDrift() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 74,
                limitInForce: 60,
                holdIsAttributed: true
            ) == false
        )
    }

    /// Plug in a full Mac with a 60% limit and it sits at 100% held by an inhibit. Ordinary
    /// under every inhibit backend, and the level alone cannot tell it from the fault below.
    @Test func aBatteryHeldAboveTheLimitByAnInhibitIsNotDrift() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 100,
                limitInForce: 60,
                holdIsAttributed: true
            ) == false
        )
    }

    @Test func nothingIsHeldBackOffTheCharger() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: false,
                isCharging: true,
                batteryLevel: 100,
                limitInForce: 60,
                holdIsAttributed: false
            ) == false
        )
    }

    // MARK: - The fault after it has finished

    /// The state a user is in when they write in: the limit went, the battery charged to
    /// full, and now nothing is charging because there is nothing left to charge. The
    /// firmware names no reason for holding, which is what separates it from the two
    /// healthy states above.
    @Test func sittingAboveTheLimitWithNothingHoldingItIsDrift() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 100,
                limitInForce: 60,
                holdIsAttributed: false
            )
        )
    }

    /// **Nil is not false.** `.firmwareRange` publishes no attribution bit, and a pass that
    /// did not spend the XPC round trip has not learned anything either. Reading either as
    /// "nothing is holding" would warn every user of that firmware that their working Mac
    /// is broken.
    @Test func anUnaskedAttributionIsNotEvidenceOfAFault() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 100,
                limitInForce: 60,
                holdIsAttributed: nil
            ) == false
        )
    }

    /// At the limit with nothing charging, the hold has nothing left to do — this is where
    /// a limit that is working ends up, and the drain case above ends here too.
    @Test func sittingExactlyAtTheLimitIsNotDrift() {
        #expect(
            ChargeHoldDrift.isDrifting(
                chargerConnected: true,
                isCharging: false,
                batteryLevel: 60,
                limitInForce: 60,
                holdIsAttributed: false
            ) == false
        )
    }
}

@Suite struct ChargeHoldDriftMonitorTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func oneDriftingReadingIsNotYetWorthAWrite() {
        var monitor = ChargeHoldDriftMonitor()
        #expect(monitor.record(isDrifting: true, at: start) == .none)
    }

    @Test func aRunThatSurvivesAMinuteIsReapplied() {
        var monitor = ChargeHoldDriftMonitor()
        _ = monitor.record(isDrifting: true, at: start)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(59)) == .none)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(60)) == .reapply)
    }

    @Test func aRunThatSurvivesTenMinutesWarnsTheUser() {
        var monitor = ChargeHoldDriftMonitor()
        _ = monitor.record(isDrifting: true, at: start)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(599)) == .reapply)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(600)) == .warnTheUser)
    }

    /// Once per run. The fault is a steady state and passes are frequent, so an unguarded
    /// warning is a notification a minute for as long as the Mac stays broken.
    @Test func theUserIsWarnedOnceAndThenTheLimitKeepsBeingReapplied() {
        var monitor = ChargeHoldDriftMonitor()
        _ = monitor.record(isDrifting: true, at: start)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(600)) == .warnTheUser)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(660)) == .reapply)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(1_800)) == .reapply)
    }

    /// Passes are driven by power-source changes, not by a timer, and a battery charging
    /// past its limit generates them seconds apart. Without a floor between re-applies, a
    /// fault BatFi cannot fix would re-write the mechanism at that rate for as long as it
    /// lasted — and under `.firmwareRange` each of those re-runs `engageSequence`, whose
    /// first write disarms the band. The cure would be worse than the fault.
    @Test func reappliesAreSpacedOutHoweverFastThePassesArrive() {
        var monitor = ChargeHoldDriftMonitor()
        _ = monitor.record(isDrifting: true, at: start)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(60)) == .reapply)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(63)) == .none)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(90)) == .none)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(120)) == .reapply)
    }

    /// The warning is a once-per-run event of its own and is not held back by the re-apply
    /// floor — a run that has been failing for ten minutes has to be able to say so on the
    /// pass it crosses that line, whatever happened three seconds earlier.
    @Test func theWarningIsNotDelayedByTheReapplyFloor() {
        var monitor = ChargeHoldDriftMonitor()
        _ = monitor.record(isDrifting: true, at: start)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(599)) == .reapply)
        #expect(monitor.record(isDrifting: true, at: start.addingTimeInterval(600)) == .warnTheUser)
    }

    @Test func aCleanReadingEndsTheRunAndRearmsTheWarning() {
        var monitor = ChargeHoldDriftMonitor()
        _ = monitor.record(isDrifting: true, at: start)
        _ = monitor.record(isDrifting: true, at: start.addingTimeInterval(600))
        #expect(monitor.record(isDrifting: false, at: start.addingTimeInterval(660)) == .none)
        #expect(monitor.driftingSince == nil)
        #expect(monitor.hasWarned == false)

        // A second, separate fault gets its own clock rather than inheriting the first's.
        let later = start.addingTimeInterval(3_600)
        #expect(monitor.record(isDrifting: true, at: later) == .none)
        #expect(monitor.record(isDrifting: true, at: later.addingTimeInterval(60)) == .reapply)
    }
}
