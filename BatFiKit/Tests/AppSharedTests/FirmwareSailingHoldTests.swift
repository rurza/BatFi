//
//  FirmwareSailingHoldTests.swift
//  BatFi
//
//  Sailing's hold where the firmware holds a band (`.firmwareRange`). An upper bound at the
//  battery's level stops charging, even a charge already in progress, so a hold that begins
//  below the limit hands the firmware a band from the resume level up to the battery. A hold
//  that began at the limit keeps the real band and writes nothing new.
//

import Foundation
import Shared
import Testing

@testable import AppShared

@Suite struct FirmwareSailingHoldTests {
    private let l5075 = SailingLevels(limit: 75, resumeLevel: 50)

    private func band(
        _ hold: inout FirmwareSailingHold,
        phase: SailingPhase? = .holding,
        backend: ChargeBackend? = .firmwareRange,
        startedAfresh: Bool = false,
        battery: Int,
        levels: SailingLevels? = nil
    ) -> FirmwareSailingHold.Band? {
        hold.heldBand(
            phase: phase,
            backend: backend,
            startedAfresh: startedAfresh,
            batteryLevel: battery,
            levels: levels ?? l5075
        )
    }

    // MARK: - Where the hold begins

    @Test func aHoldInsideTheRangeHoldsAtTheBattery() {
        var hold = FirmwareSailingHold()
        #expect(band(&hold, startedAfresh: true, battery: 60) == .init(limit: 60, resumeLevel: 50))
        #expect(hold.heldLevel == 60)
    }

    /// At the limit the real band already holds: nothing new is asked for, and nothing is
    /// asked for as the battery drifts down from it either.
    @Test func aHoldThatBeganAtTheLimitKeepsTheRealBand() {
        var hold = FirmwareSailingHold()
        #expect(band(&hold, startedAfresh: true, battery: 75) == nil)
        #expect(band(&hold, battery: 74) == nil)
        #expect(band(&hold, battery: 60) == nil)
        #expect(!hold.keepsAValueOtherThan(75))
    }

    /// A battery above the limit is left to the real band, which brings it down to the limit
    /// as it does with sailing off.
    @Test func aBatteryAboveTheLimitKeepsTheRealBand() {
        var hold = FirmwareSailingHold()
        #expect(band(&hold, startedAfresh: true, battery: 78) == nil)
        #expect(band(&hold, battery: 74) == nil)
    }

    // MARK: - For the length of the hold

    @Test func theHeldValueIsKeptAsTheBatteryDrifts() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        #expect(band(&hold, battery: 59) == .init(limit: 60, resumeLevel: 50))
        #expect(band(&hold, battery: 52) == .init(limit: 60, resumeLevel: 50))
        #expect(hold.keepsAValueOtherThan(75))
    }

    /// The write takes a moment to bite. A battery that climbed past the held value moves it up
    /// to the battery: an upper bound under the battery would drain it, and sailing only
    /// withholds charging.
    @Test func aBatteryThatRoseMovesTheHeldValueUp() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        #expect(band(&hold, battery: 61) == .init(limit: 61, resumeLevel: 50))
        #expect(band(&hold, battery: 60) == .init(limit: 61, resumeLevel: 50))
    }

    @Test func aBatteryThatRoseToTheLimitHandsBackTheRealBand() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 73)
        #expect(band(&hold, battery: 75) == nil)
        #expect(band(&hold, battery: 74) == nil)
        #expect(!hold.keepsAValueOtherThan(75))
    }

    @Test func theUpperBoundIsNeverUnderTheBattery() {
        var hold = FirmwareSailingHold()
        var fresh = true
        for battery in [60, 62, 61, 64, 58, 70, 66, 74, 72] {
            if let held = band(&hold, startedAfresh: fresh, battery: battery) {
                #expect(held.limit >= battery)
            }
            fresh = false
        }
    }

    // MARK: - The resume level

    /// A battery held exactly at the resume level has no room under it for the band's lower
    /// bound: the firmware is handed one point under it, so it does not charge before BatFi
    /// sees the battery go below the resume level and hands it the real band.
    @Test func aHoldAtTheResumeLevelPutsTheLowerBoundOnePointUnder() {
        var hold = FirmwareSailingHold()
        #expect(band(&hold, startedAfresh: true, battery: 50) == .init(limit: 50, resumeLevel: 49))
    }

    @Test func aHoldJustAboveTheResumeLevelKeepsTheResumeLevel() {
        var hold = FirmwareSailingHold()
        #expect(band(&hold, startedAfresh: true, battery: 51) == .init(limit: 51, resumeLevel: 50))
    }

    // MARK: - Fresh starts and level changes

    /// A hold that starts afresh — a wake, the end of Run on Battery — is re-established at the
    /// battery's level, so a band whose upper bound the battery has since fallen away from
    /// cannot start a charge up to it.
    @Test func aFreshStartReestablishesTheHoldAtTheBattery() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        _ = band(&hold, battery: 58)
        #expect(band(&hold, startedAfresh: true, battery: 55) == .init(limit: 55, resumeLevel: 50))
    }

    @Test func aFreshStartAfterAHoldAtTheLimitHoldsAtTheBattery() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 75)
        _ = band(&hold, battery: 70)
        #expect(band(&hold, startedAfresh: true, battery: 66) == .init(limit: 66, resumeLevel: 50))
    }

    /// A raised limit does not move the hold: the held band stays as it is and the new limit
    /// reaches the firmware when charging resumes.
    @Test func aRaisedLimitKeepsTheHeldValue() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        #expect(band(&hold, battery: 59, levels: SailingLevels(limit: 80, resumeLevel: 50)) == .init(limit: 60, resumeLevel: 50))
    }

    /// A hold that began at the old limit keeps that value as its upper bound, so raising
    /// the limit writes nothing that could start a charge.
    @Test func aRaisedLimitOverAHoldAtTheOldLimitKeepsTheOldLimit() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 75)
        #expect(band(&hold, battery: 74, levels: SailingLevels(limit: 80, resumeLevel: 50)) == .init(limit: 75, resumeLevel: 50))
        #expect(hold.keepsAValueOtherThan(80))
    }

    @Test func aLimitLoweredUnderTheHeldValueMovesTheHoldToTheBattery() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 70)
        #expect(band(&hold, battery: 68, levels: SailingLevels(limit: 69, resumeLevel: 50)) == .init(limit: 68, resumeLevel: 50))
    }

    /// Lowered to the battery or under it, the real band takes over and the firmware brings
    /// the battery down to the limit, as it does with sailing off.
    @Test func aLimitLoweredToTheBatteryHandsBackTheRealBand() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 70)
        #expect(band(&hold, battery: 68, levels: SailingLevels(limit: 65, resumeLevel: 50)) == nil)
    }

    /// The lower bound changes, so the band is written anyway: it is written at the battery,
    /// where an upper bound cannot start a charge.
    @Test func aChangedResumeLevelReestablishesTheHoldAtTheBattery() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        #expect(band(&hold, battery: 58, levels: SailingLevels(limit: 75, resumeLevel: 45)) == .init(limit: 58, resumeLevel: 45))
    }

    // MARK: - Not holding

    @Test func chargingAsksForNothingAndClearsTheHold() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        #expect(band(&hold, phase: .charging, battery: 49) == nil)
        #expect(hold.heldLevel == nil)
        #expect(!hold.keepsAValueOtherThan(75))
    }

    @Test func noPhaseAsksForNothing() {
        var hold = FirmwareSailingHold()
        _ = band(&hold, startedAfresh: true, battery: 60)
        #expect(band(&hold, phase: nil, battery: 60) == nil)
        #expect(hold.heldLevel == nil)
    }

    @Test func anotherBackendAsksForNothing() {
        var hold = FirmwareSailingHold()
        #expect(band(&hold, backend: .systemChargeLimit, startedAfresh: true, battery: 60) == nil)
        #expect(band(&hold, backend: .chte, startedAfresh: true, battery: 60) == nil)
        #expect(band(&hold, backend: nil, startedAfresh: true, battery: 60) == nil)
    }

    // MARK: - A held band the helper did not take

    /// The client sends the one-value call in place of a range the helper refused. Then the
    /// held band is not in force, and BatFi goes back to today's behaviour.
    @Test func aHeldBandThatDidNotGoOutStopsTheHold() {
        var hold = FirmwareSailingHold()
        let held = band(&hold, startedAfresh: true, battery: 60)
        #expect(hold.canHoldByBand)
        hold.recordApply(of: held, wentOutAsRange: false)
        #expect(!hold.canHoldByBand)
        #expect(hold.heldLevel == nil)
        #expect(band(&hold, startedAfresh: true, battery: 60) == nil)
    }

    @Test func aHeldBandThatWentOutKeepsTheHold() {
        var hold = FirmwareSailingHold()
        let held = band(&hold, startedAfresh: true, battery: 60)
        hold.recordApply(of: held, wentOutAsRange: true)
        #expect(hold.canHoldByBand)
        #expect(band(&hold, battery: 60) == .init(limit: 60, resumeLevel: 50))
    }

    /// Only a held band's apply says anything about the held band: the real band going out as
    /// the one-value call is today's fallback, decided before the hold is asked for.
    @Test func noHeldBandRecordsNothing() {
        var hold = FirmwareSailingHold()
        hold.recordApply(of: nil, wentOutAsRange: false)
        #expect(hold.canHoldByBand)
    }
}
