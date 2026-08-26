//
//  ChargeDirectionTests.swift
//  BatFi
//
//  The one rule `SystemChargeDrain` and `SystemChargeTopUp` both read. Each of them requires a
//  *named* direction rather than the absence of the other one, which is the whole point: the
//  first version of this answered a `Bool` — "is charge flowing in" — and the drain took
//  `false` as proof of a drain. A battery resting at exactly 0 mA answers `false` to that
//  question, so a full battery sitting idle on the charger was reported as discharging.
//
//  Measured 2026-08-26 12:57 on the shipped fix: 100%, limit in force 75%, `Amperage` 0,
//  `InstantAmperage` 0, `FullyCharged` true, menu power distribution 8.2 W in → 8.2 W to the
//  system and nothing to the battery. The menu read "Discharging to the limit".
//

import Foundation
import Testing

@testable import AppShared

@Suite struct ChargeDirectionTests {
    // MARK: - The three directions

    @Test func iokitAloneIsEnoughToSayChargeIsGoingIn() {
        #expect(ChargeDirection.flow(isCharging: true, batteryPower: nil) == .intoTheBattery)
    }

    /// The regression. `batteryPower` is the battery as a target when negative, so zero is
    /// neither direction — and "not going in" was never the same as "coming out".
    @Test func anIdleBatteryIsNeitherChargingNorDischarging() {
        #expect(ChargeDirection.flow(isCharging: false, batteryPower: 0) == .idle)
    }

    @Test func powerLeavingTheBatteryIsADischarge() {
        #expect(ChargeDirection.flow(isCharging: false, batteryPower: 7.4) == .outOfTheBattery)
    }

    @Test func powerEnteringTheBatteryIsACharge() {
        #expect(ChargeDirection.flow(isCharging: false, batteryPower: -7.0) == .intoTheBattery)
    }

    /// Sensor noise around zero must not read as a drain — that is the reading the bug was
    /// about, and a hundredth of a watt is not a battery being run down.
    @Test func noiseAroundZeroIsStillIdle() {
        for p in [Float(0.04), -0.04, 0.09, -0.09] {
            #expect(ChargeDirection.flow(isCharging: false, batteryPower: p) == .idle, "\(p)")
        }
    }

    // MARK: - Which source wins

    /// The ~17s window measured on 26A5416b: the SMC reports current entering the battery while
    /// `AppleSmartBattery` still says 0 mA. Without this the label is wrong for the whole first
    /// third of a minute of every top-up.
    @Test func theSMCLeadsIOKitIntoACharge() {
        #expect(ChargeDirection.flow(isCharging: false, batteryPower: -46.2) == .intoTheBattery)
    }

    /// The asymmetry `SystemChargeHold` already applies: an SMC read of ~0 cannot contradict
    /// IOKit's `true`, because a battery resting at 0 mA and one whose SMC read is merely stale
    /// look identical from here.
    @Test func anIdleSMCReadCannotContradictIOKit() {
        #expect(ChargeDirection.flow(isCharging: true, batteryPower: 0) == .intoTheBattery)
    }

    /// Nor can an outward one. IOKit saying "charging" while the SMC shows power leaving is a
    /// disagreement neither reading can settle, and claiming a discharge on it is the failure
    /// this file exists to prevent.
    @Test func anOutwardSMCReadCannotContradictIOKitEither() {
        #expect(ChargeDirection.flow(isCharging: true, batteryPower: 7.4) == .intoTheBattery)
    }

    // MARK: - No answer at all

    /// A helper that cannot answer leaves no way to tell a drain from a full battery resting,
    /// and `PowerState` carries no amperage of its own. Unknown rather than a guess: the label
    /// that depends on this says nothing rather than picking one and being wrong half the time.
    @Test func noSMCAnswerAndNotChargingIsUnknown() {
        #expect(ChargeDirection.flow(isCharging: false, batteryPower: nil) == .unknown)
    }
}
