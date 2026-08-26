//
//  ChargeDirection.swift
//
//
//  Which way charge is moving, from the two sources that can answer and that disagree.
//
//  Read by `SystemChargeDrain` and `SystemChargeTopUp`. Each of them requires a **named**
//  direction, and that is the whole design: the first version answered a `Bool` — "is charge
//  flowing in" — and the drain took `false` as proof of a drain. A battery resting at exactly
//  0 mA answers `false` to that question too, so a full battery sitting idle on the charger was
//  reported as discharging to the limit. Measured 2026-08-26 at 100% against a 75% limit with
//  `Amperage` 0 and 8.2 W going straight past the battery to the system.
//
//  So there is no complement here to get wrong. A reading that is neither direction is claimed
//  by neither state, rather than falling through to whichever one happened to test for an
//  absence.
//

import Foundation

public enum ChargeDirection {
    /// Which way charge is moving, or that nobody can say.
    public enum Flow: Equatable, Sendable {
        /// The battery is being charged.
        case intoTheBattery
        /// The battery is being run down — the only reading that supports a drain.
        case outOfTheBattery
        /// On the charger and neither: a full battery resting, or one held where it is.
        case idle
        /// No evidence either way. `PowerState` carries no amperage, so when the helper cannot
        /// answer there is nothing to fall back on — and a guess here is a sentence on screen
        /// that is wrong half the time.
        case unknown
    }

    /// Below this many watts the battery is resting. `PowerDistributionInfo` is a live SMC
    /// reading and jitters around zero; a hundredth of a watt is not a battery being run down,
    /// and reading it as one is the bug this guards. Matches the precision the menu displays.
    static let restingThreshold: Float = 0.1

    /// - Parameters:
    ///   - isCharging: `kIOPSIsChargingKey`. Free — it is already on every `PowerState` — and it
    ///     lags. It is a `Bool`, so it can only ever assert a charge, never a discharge.
    ///   - batteryPower: `PowerDistributionInfo.batteryPower`, the signed SMC reading, or **nil
    ///     where it was not asked**. Negative is the battery as a *target* rather than a source
    ///     — the sign convention `PowerGraph` renders — so negative is charge going in.
    ///
    /// The SMC leads IOKit into a charge and only ever adds: measured ~17s on 26A5416b, where it
    /// reported 46.2 W entering the battery while `AppleSmartBattery` still said 0 mA. So an
    /// inward SMC reading settles it.
    ///
    /// In the other direction IOKit wins. An SMC reading of ~0, or even one pointing outward,
    /// cannot contradict `isCharging` — a battery resting at 0 mA and one whose SMC read is
    /// merely stale look identical from here, and the cost of getting it wrong is asymmetric:
    /// claiming a discharge over a battery that is charging is the failure this file exists to
    /// prevent, while a top-up label that lingers a few seconds into the drain that follows is
    /// nothing anyone reports.
    public static func flow(isCharging: Bool, batteryPower: Float?) -> Flow {
        guard let batteryPower else {
            return isCharging ? .intoTheBattery : .unknown
        }
        if batteryPower < -restingThreshold { return .intoTheBattery }
        if isCharging { return .intoTheBattery }
        if batteryPower > restingThreshold { return .outOfTheBattery }
        return .idle
    }
}
