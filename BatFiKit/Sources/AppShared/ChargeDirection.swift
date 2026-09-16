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
//  Which source wins was the second thing to get wrong here. IOKit's `isCharging` was decisive
//  for a charge and an outward SMC reading could not contradict it, on the reasoning that a
//  stale SMC read and a resting battery are indistinguishable. True of a reading near zero, and
//  false of nine watts: measured 2026-09-16, a limit lowered under a resting battery put macOS
//  into its drain immediately while `IsCharging` stayed true for 43 seconds, and the menu called
//  it a charge to 100% for all of them. The threshold, not the source, is what separates a
//  reading that can settle the question from one that cannot.
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

    /// Below this many watts the battery is resting.
    ///
    /// `PowerDistributionInfo` is a live SMC reading. Measured 2026-08-26 13:59–14:03 with a
    /// full battery on the charger: it crossed **0.1 W nine times in four minutes**, across 90
    /// successful reads in the same window — so the helper was answering and the value itself
    /// was moving. A resting battery trades small amounts with the adapter and briefly
    /// supplements it whenever a load burst outruns it, and neither is a battery being run
    /// down. The first threshold here was 0.1 W and it flapped the label, and with it a "New
    /// mode" notification, every time.
    ///
    /// One watt instead. A drain macOS performs on purpose runs at several watts — the top-up
    /// measured the same day pushed 7 W the other way — so nothing real is lost, and the noise
    /// no longer reaches.
    static let restingThreshold: Float = 1.0

    /// - Parameters:
    ///   - isCharging: `kIOPSIsChargingKey`. Free — it is already on every `PowerState` — and it
    ///     lags. It is a `Bool`, so it can only ever assert a charge, never a discharge.
    ///   - batteryPower: `PowerDistributionInfo.batteryPower`, the signed SMC reading, or **nil
    ///     where it was not asked**. Negative is the battery as a *target* rather than a source
    ///     — the sign convention `PowerGraph` renders — so negative is charge going in.
    ///
    /// The SMC leads IOKit in **both** directions, so a reading that clears the resting band
    /// settles it either way. Into a charge: measured ~17s on 26A5416b, the SMC reporting
    /// 46.2 W entering the battery while `AppleSmartBattery` still said 0 mA. Out of one:
    /// measured 43s on 2026-09-16, `IsCharging` still true — with an `AvgTimeToFull` of 33
    /// minutes behind it — while 9.0 W left the pack and macOS had already declared
    /// `DischargingToMCL`. `isCharging` is a `Bool`: it can only assert a charge, and nothing
    /// in it expires, so it goes on asserting one until the next power-source notification
    /// happens to arrive.
    ///
    /// What IOKit still wins is everything *inside* the band. An SMC read of ~0 cannot
    /// contradict `isCharging`, because a battery resting at 0 mA and one whose SMC read is
    /// merely stale look identical from here, and claiming a discharge on that is the failure
    /// this file exists to prevent. The threshold is the whole distinction: a battery supplying
    /// the system at several watts is not being charged under any reading, whoever says
    /// otherwise, and an earlier version of this let `isCharging` outrank exactly that — which
    /// is how a drain the user had just asked for was announced as a charge to 100%, with the
    /// nine watts leaving the battery drawn one section below the sentence.
    public static func flow(isCharging: Bool, batteryPower: Float?) -> Flow {
        guard let batteryPower else {
            return isCharging ? .intoTheBattery : .unknown
        }
        if batteryPower < -restingThreshold { return .intoTheBattery }
        if batteryPower > restingThreshold { return .outOfTheBattery }
        if isCharging { return .intoTheBattery }
        return .idle
    }
}
