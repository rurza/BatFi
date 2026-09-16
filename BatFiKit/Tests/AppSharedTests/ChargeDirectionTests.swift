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
        for p in [Float(0.4), -0.4, 0.9, -0.9] {
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

    /// But a *decisive* outward one can, and the rule that said otherwise shipped.
    ///
    /// Measured 2026-09-16 12:48:53–12:49:36: the limit was lowered 85% → 75% under a battery
    /// resting at 85%, macOS declared `DischargingToMCL` 11 ms later, and `IsCharging` stayed
    /// **true for 43 seconds** — with an `AvgTimeToFull` of 33 minutes, so the menu offered
    /// "Time to Charge 33 min" over a battery it was draining. The SMC read 9.0 W leaving,
    /// rendered in the same menu one section below the label that called it a charge to 100%.
    /// IOKit only corrected itself when powerd posted the next `chargingiconography`.
    ///
    /// The staleness is symmetric, so the tie-break is too: the SMC leads IOKit *out* of a
    /// charge exactly as it leads it in, and `isCharging` is a `Bool` that can go on asserting
    /// a charge long after the current reverses. What cannot be settled is a reading near zero
    /// — kept above — where a resting battery and a stale read look identical. Nine watts
    /// leaving the pack is not that: a battery supplying the system at several watts is not
    /// being charged under any reading, whatever IOKit still says.
    @Test func aDecisiveOutwardSMCReadOutranksAStaleIOKitCharge() {
        #expect(ChargeDirection.flow(isCharging: true, batteryPower: 9.0) == .outOfTheBattery)
    }

    /// The threshold is what separates the two, and it is the same one everywhere else: only a
    /// reading that clears the resting band may overrule `isCharging`. Jitter never does.
    @Test func jitterSizedOutwardReadsStillCannotContradictIOKit() {
        for noise in [Float(0.1), 0.4, 0.9, 1.0] {
            #expect(ChargeDirection.flow(isCharging: true, batteryPower: noise) == .intoTheBattery, "\(noise)")
        }
    }

    // MARK: - No answer at all

    /// A helper that cannot answer leaves no way to tell a drain from a full battery resting,
    /// and `PowerState` carries no amperage of its own. Unknown rather than a guess: the label
    /// that depends on this says nothing rather than picking one and being wrong half the time.
    @Test func noSMCAnswerAndNotChargingIsUnknown() {
        #expect(ChargeDirection.flow(isCharging: false, batteryPower: nil) == .unknown)
    }
}
