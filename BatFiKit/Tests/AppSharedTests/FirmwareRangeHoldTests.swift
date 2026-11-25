//
//  FirmwareRangeHoldTests.swift
//  BatFi
//
//  Under `.firmwareRange` the firmware charges to the limit and then holds while the battery
//  drifts down to the band's lower bound. BatFi used to read every level below the limit as
//  `.charging`, so the menu said "Charging" through the whole drift while nothing charged,
//  and the green light could not be offered at all. This is the one signal both now follow.
//
//  At an 80% limit the band is 75–80 (`FirmwareChargeRange.band`).
//

import Foundation
import Testing

@testable import AppShared
import Shared

@Suite struct FirmwareRangeHoldTests {
    private func isHolding(
        backend: ChargeBackend? = .firmwareRange,
        chargerConnected: Bool = true,
        batteryLevel: Int,
        limitInForce: Int = 80,
        batteryPower: Float?,
        batFiIsDischarging: Bool = false
    ) -> Bool {
        FirmwareRangeHold.isHolding(
            backend: backend,
            chargerConnected: chargerConnected,
            batteryLevel: batteryLevel,
            limitInForce: limitInForce,
            batteryPower: batteryPower,
            batFiIsDischarging: batFiIsDischarging
        )
    }

    // MARK: - The drift

    @Test func aRestingBatteryInsideTheBandIsHeld() {
        #expect(isHolding(batteryLevel: 78, batteryPower: 0))
    }

    /// The battery supplying a load burst the adapter could not cover is still not charging.
    @Test func aBatteryGivingChargeInsideTheBandIsHeld() {
        #expect(isHolding(batteryLevel: 78, batteryPower: 4.5))
    }

    /// A resting battery dips a fraction of a watt into the pack several times a minute; none
    /// of that is the firmware resuming (`ChargeDirection.restingThreshold`).
    @Test func aDipInsideTheRestingBandIsStillHeld() {
        #expect(isHolding(batteryLevel: 78, batteryPower: -0.6))
    }

    @Test func theLowerBoundItselfIsInsideTheBand() {
        #expect(isHolding(batteryLevel: 75, batteryPower: 0))
    }

    /// The firmware resumed charging at the lower bound: current going in is `.charging`.
    @Test func chargeGoingInInsideTheBandIsNotHeld() {
        #expect(isHolding(batteryLevel: 78, batteryPower: -30) == false)
        #expect(isHolding(batteryLevel: 75, batteryPower: -30) == false)
    }

    /// Below the band and not charging is something else — calibration, a hot battery, an
    /// adapter that cannot keep up — and keeps the behaviour it had.
    @Test func belowTheLowerBoundIsNotThisHold() {
        #expect(isHolding(batteryLevel: 74, batteryPower: 0) == false)
        #expect(isHolding(batteryLevel: 40, batteryPower: 0) == false)
    }

    /// The band follows the limit in force, not a fixed number.
    @Test func theBandIsTheOneForTheLimitInForce() {
        #expect(isHolding(batteryLevel: 56, limitInForce: 60, batteryPower: 0))
        #expect(isHolding(batteryLevel: 54, limitInForce: 60, batteryPower: 0) == false)
    }

    /// The floor on the lower bound applies here too: at a 12% limit the band is 10–12.
    @Test func theBandsFloorIsHonoured() {
        #expect(isHolding(batteryLevel: 10, limitInForce: 12, batteryPower: 0))
        #expect(isHolding(batteryLevel: 9, limitInForce: 12, batteryPower: 0) == false)
    }

    // MARK: - Sailing's band

    /// With sailing the firmware is handed a band reaching down to the resume level, so the
    /// whole of it is the hold — not today's five points under the limit.
    @Test func sailingBandCountsAsInsideDownToTheResumeLevel() {
        #expect(FirmwareRangeHold.isInsideBand(batteryLevel: 71, limitInForce: 80, resumeLevel: 70))
        #expect(!FirmwareRangeHold.isInsideBand(batteryLevel: 71, limitInForce: 80))   // today's 75–80
        #expect(!FirmwareRangeHold.isInsideBand(batteryLevel: 69, limitInForce: 80, resumeLevel: 70))
    }

    @Test func holdingInsideASailingBandIsSeen() {
        #expect(FirmwareRangeHold.isHolding(backend: .firmwareRange, chargerConnected: true, batteryLevel: 72, limitInForce: 80, batteryPower: 0, batFiIsDischarging: false, resumeLevel: 70))
    }

    /// The firmware resuming inside the wider band is charging, as it is inside today's.
    @Test func chargeGoingInInsideASailingBandIsNotHeld() {
        #expect(!FirmwareRangeHold.isHolding(backend: .firmwareRange, chargerConnected: true, batteryLevel: 72, limitInForce: 80, batteryPower: -30, batFiIsDischarging: false, resumeLevel: 70))
    }

    /// The band is the one the helper writes, so a resume level that is not below the limit
    /// is today's band, exactly as `FirmwareChargeRange.band` hands it to the firmware.
    @Test func aResumeLevelThatIsNoBandLeavesTodaysBand() {
        #expect(FirmwareRangeHold.isInsideBand(batteryLevel: 75, limitInForce: 80, resumeLevel: 80))
        #expect(!FirmwareRangeHold.isInsideBand(batteryLevel: 74, limitInForce: 80, resumeLevel: 80))
    }

    // MARK: - Where it never applies

    @Test func noChargerIsNoHold() {
        #expect(isHolding(chargerConnected: false, batteryLevel: 78, batteryPower: 5) == false)
    }

    @Test func otherBackendsNeverHoldThisWay() {
        for backend in ChargeBackend.allCases where backend != .firmwareRange {
            #expect(isHolding(backend: backend, batteryLevel: 78, batteryPower: 0) == false, "\(backend.rawValue)")
        }
        #expect(isHolding(backend: nil, batteryLevel: 78, batteryPower: 0) == false)
    }

    /// No SMC reading is no evidence, and IOKit's lagging flag is not asked to stand in for
    /// one: the mode stays what it was before this rule existed.
    @Test func anUnknownReadingIsNoHold() {
        #expect(isHolding(batteryLevel: 78, batteryPower: nil) == false)
    }

    /// BatFi's own discharge reads as charge leaving the battery, and is not the firmware's.
    @Test func batFisOwnDischargeIsNoHold() {
        #expect(isHolding(batteryLevel: 78, batteryPower: 6, batFiIsDischarging: true) == false)
    }
}
