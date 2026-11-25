//
//  DischargeResumeHold.swift
//
//
//  "Resume Discharging" under Apple's charge limit, shown as the drain it resumes from the click.
//
//  Ending a discharge pause lowers the applied limit from the frozen one back to the user's.
//  powerd adopts that up to ~45 s later and current takes ~25 s more to turn round, and for
//  all of it `ChargeLimitRaiseWindow` holds back the states of a battery above the limit — the
//  drain among them — so the pass published plain "Inhibiting charging" and the plug until the
//  window closed and the drain showed again, quietly. The owner wants every change shown at
//  once: the click publishes the drain (`ChargingAheadOfApply.onEndingOverride`), and this
//  keeps the passes in that window publishing it too. Once the window closes the readings are
//  genuine and decide on their own.
//
//  Here rather than in `ChargingManager` because `AppCore` has no test target.
//

import Foundation

public struct DischargeResumeHold: Sendable {
    public private(set) var isArmed = false

    public init() {}

    /// "Resume Discharging" was clicked and published the drain.
    public mutating func arm() {
        isArmed = true
    }

    /// Whether the drain is published this pass whatever the readings say: armed, no override
    /// in force, and the battery above the limit macOS drains to.
    public func holdsDrain(batteryLevel: Int, limitInForce: Int, overrideInForce: UserTempChargingMode?) -> Bool {
        isArmed && overrideInForce == nil && batteryLevel > limitInForce
    }

    /// Records this pass's window verdict, after the apply. The hold ends with the window — the
    /// above-limit states are genuine from then on — or when an override is armed over it.
    ///
    /// - Parameters:
    ///   - suppressesAboveLimitStates: `ChargeLimitRaiseWindow.Verdict`'s, this pass.
    ///   - overrideInForce: the override this pass worked its limit out under.
    ///   - passIsStale: that override is no longer the one published — a pass begun under the
    ///     pause, still applying its frozen limit when Resume was clicked. It says nothing about
    ///     the lowering, so it neither ends the hold nor is held.
    public mutating func record(suppressesAboveLimitStates: Bool, overrideInForce: UserTempChargingMode?, passIsStale: Bool) {
        guard isArmed, !passIsStale else { return }
        if !suppressesAboveLimitStates || overrideInForce != nil {
            isArmed = false
        }
    }
}
