//
//  SystemChargeTopUpLatchTests.swift
//  BatFi
//
//  MPX-43: during a macOS calibration charge the battery sits at ~100% and the SMC's reading
//  wanders across the resting band, so the per-snapshot rules flipped the label between
//  "macOS is calibrating the battery" and "Discharging to the limit" every minute or two, with a
//  "New mode" banner each time. The latch keeps the top-up once it has genuinely begun.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SystemChargeTopUpLatchTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    private func record(
        _ latch: inout SystemChargeTopUpLatch,
        level: Int,
        limit: Int = 80,
        isCharging: Bool = false,
        power: Float?,
        chargerConnected: Bool = true,
        drainsItself: Bool = true,
        at seconds: TimeInterval
    ) -> SystemChargeTopUpLatch.Verdict {
        latch.record(
            chargerConnected: chargerConnected,
            batteryLevel: level,
            limitInForce: limit,
            isCharging: isCharging,
            batteryPower: power,
            mechanismDrainsToLimitItself: drainsItself,
            at: at(seconds)
        )
    }

    // MARK: - Arming

    @Test func aChargeConfirmedByTheSMCArmsTheLatch() {
        var latch = SystemChargeTopUpLatch()
        let verdict = record(&latch, level: 90, isCharging: true, power: -7.0, at: 0)
        #expect(verdict.isToppingUp)
        #expect(verdict.isDraining == false)
        #expect(latch.isLatched)
    }

    @Test func theRestingPlateauAtFullArmsTheLatch() {
        var latch = SystemChargeTopUpLatch()
        let verdict = record(&latch, level: 100, power: 0.2, at: 0)
        #expect(verdict.isToppingUp)
        #expect(latch.isLatched)
    }

    @Test func aMechanismThatDoesNotDrainItselfNeverArms() {
        var latch = SystemChargeTopUpLatch()
        let verdict = record(&latch, level: 100, isCharging: true, power: -7.0, drainsItself: false, at: 0)
        #expect(verdict.isToppingUp == false)
        #expect(latch.isLatched == false)
    }

    // MARK: - The flap this exists to stop

    /// The customer's shape: the plateau at 100% with an outward burst between resting reads.
    @Test func anOutwardBurstAtThePlateauKeepsTheTopUp() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)

        let burst = record(&latch, level: 100, power: 3.5, at: 3)
        #expect(burst.isToppingUp)
        #expect(burst.isDraining == false)

        let rest = record(&latch, level: 100, power: 0.1, at: 6)
        #expect(rest.isToppingUp)
        #expect(rest.isDraining == false)
    }

    /// The drift check is fed what the reading itself says, so the latch has to hand it over.
    @Test func theSnapshotAnswersSurviveUnderTheLatch() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)
        let burst = record(&latch, level: 100, power: 3.5, at: 3)
        #expect(burst.snapshotIsToppingUp == false)
        #expect(burst.snapshotIsDraining)
    }

    // MARK: - Releasing

    @Test func twoMinutesOfOutwardFlowReleasesIt() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)

        var verdict = record(&latch, level: 100, power: 8.4, at: 10)
        for second in stride(from: 13.0, through: 127.0, by: 3) {
            verdict = record(&latch, level: 100, power: 8.4, at: second)
            #expect(verdict.isToppingUp, "released after only \(second - 10)s of outward flow")
        }
        verdict = record(&latch, level: 100, power: 8.4, at: 130)
        #expect(verdict.isToppingUp == false)
        #expect(verdict.isDraining)
        #expect(verdict.release == .sustainedOutwardFlow)
        #expect(latch.isLatched == false)
    }

    @Test func anyReadingThatIsNotOutwardRestartsTheTwoMinutes() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)
        _ = record(&latch, level: 100, power: 8.4, at: 10)
        _ = record(&latch, level: 100, power: 0.3, at: 100)
        _ = record(&latch, level: 100, power: 8.4, at: 110)

        #expect(record(&latch, level: 100, power: 8.4, at: 200).isToppingUp)
        let released = record(&latch, level: 100, power: 8.4, at: 230)
        #expect(released.isToppingUp == false)
        #expect(released.release == .sustainedOutwardFlow)
    }

    @Test func unpluggingReleasesIt() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)
        let verdict = record(&latch, level: 100, power: 8.0, chargerConnected: false, at: 3)
        #expect(verdict.isToppingUp == false)
        #expect(verdict.release == .chargerUnplugged)
        #expect(latch.isLatched == false)
    }

    @Test func fallingTwoPointsBelowThePeakReleasesIt() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 95, isCharging: true, power: -7.0, at: 0)
        _ = record(&latch, level: 100, isCharging: true, power: -2.0, at: 300)

        let onePointDown = record(&latch, level: 99, power: 0.2, at: 600)
        #expect(onePointDown.isToppingUp)

        let twoPointsDown = record(&latch, level: 98, power: 0.2, at: 603)
        #expect(twoPointsDown.isToppingUp == false)
        #expect(twoPointsDown.release == .droppedBelowPeak)
    }

    @Test func reachingTheLimitInForceReleasesIt() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)
        // The user raises the limit to 100 while the battery rests there.
        let verdict = record(&latch, level: 100, limit: 100, power: 0.2, at: 3)
        #expect(verdict.isToppingUp == false)
        #expect(verdict.release == .reachedLimit)
    }

    @Test func aReleasedLatchReportsTheReadingAsItIs() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)
        _ = record(&latch, level: 100, power: 8.0, chargerConnected: false, at: 3)
        let afterwards = record(&latch, level: 99, power: 0.2, at: 6)
        #expect(afterwards.isToppingUp == false)
        #expect(afterwards.release == nil)
    }

    @Test func resetDropsTheLatch() {
        var latch = SystemChargeTopUpLatch()
        _ = record(&latch, level: 100, power: 0.2, at: 0)
        latch.reset()
        #expect(latch.isLatched == false)
        #expect(record(&latch, level: 100, power: 3.5, at: 3).isDraining)
    }

    // MARK: - The false top-up fixed in 4.0.1 must not come back through the latch

    /// Measured 2026-09-16: the limit lowered from above to 80% under an 85% battery, macOS
    /// draining 9.0 W at once while IOKit went on reporting `IsCharging` for 43 seconds.
    @Test func theLimitDroppingUnderAChargingBatteryNeverArms() {
        var latch = SystemChargeTopUpLatch()
        for second in stride(from: 0.0, through: 43.0, by: 3) {
            let verdict = record(&latch, level: 85, isCharging: true, power: 9.0, at: second)
            #expect(verdict.isToppingUp == false)
            #expect(verdict.isDraining)
        }
        let corrected = record(&latch, level: 85, isCharging: false, power: 9.0, at: 46)
        #expect(corrected.isDraining)
        #expect(latch.isLatched == false)
    }

    /// The same moment caught on a pass just before the drain shows on the SMC: IOKit's stale
    /// charge decides the in-band reading, so the snapshot still says top-up, but that is IOKit
    /// alone and must not hold the label for two minutes of the drain that follows.
    @Test func aStaleChargeInsideTheRestingBandDoesNotArm() {
        var latch = SystemChargeTopUpLatch()
        let stale = record(&latch, level: 85, isCharging: true, power: 0.3, at: 0)
        #expect(stale.isToppingUp)
        #expect(latch.isLatched == false)

        let drain = record(&latch, level: 85, isCharging: true, power: 9.0, at: 3)
        #expect(drain.isToppingUp == false)
        #expect(drain.isDraining)
    }

    @Test func aChargeWithNoSMCReadingDoesNotArm() {
        var latch = SystemChargeTopUpLatch()
        #expect(record(&latch, level: 85, isCharging: true, power: nil, at: 0).isToppingUp)
        #expect(latch.isLatched == false)
        #expect(record(&latch, level: 85, isCharging: true, power: 9.0, at: 3).isDraining)
    }
}
