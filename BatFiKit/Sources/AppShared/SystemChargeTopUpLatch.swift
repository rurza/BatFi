//
//  SystemChargeTopUpLatch.swift
//
//
//  Memory across passes for the macOS top-up, on top of the per-snapshot rules.
//
//  `SystemChargeTopUp` and `SystemChargeDrain` answer from one SMC reading each, and a
//  calibration charge spends most of its life on a plateau at ~100% where that reading
//  wanders: a load burst outruns the adapter, the battery supplements it for a moment past
//  the resting threshold, and the next read is back at rest. MPX-43, macOS 27, limit 80%:
//  the menu label and a "New mode" banner flipped between "macOS is calibrating the battery" and
//  "Discharging to the limit" every minute or two for as long as the plateau lasted.
//
//  So once the top-up has genuinely begun it is kept until something that actually ends an
//  episode happens — the charger coming out, the level falling clearly off its peak, a drain
//  that persists, or the battery reaching the limit. The per-snapshot rules are unchanged and
//  still decide everything while the latch is not set.
//

import Foundation

public struct SystemChargeTopUpLatch: Equatable, Sendable {
    /// How long charge must go on leaving the battery, without a break, before the top-up is
    /// taken to be over. The owner's figure: two minutes, not one.
    public static let releaseAfterOutwardFlow: TimeInterval = 120
    /// How far below the episode's peak the level must fall to end it.
    public static let releaseBelowPeak = 2

    /// Why a latched top-up was let go, for the log line that says so.
    public enum Release: Equatable, Sendable {
        case chargerUnplugged
        case droppedBelowPeak
        case sustainedOutwardFlow
        case reachedLimit
    }

    public struct Verdict: Equatable, Sendable {
        /// What the label says: the latch where it holds, the reading where it does not.
        public let isToppingUp: Bool
        public let isDraining: Bool
        /// What this reading alone says, before the latch — `ChargeHoldDrift` is fed these, so
        /// that the latch changes the label and nothing about when a limit is re-applied.
        public let snapshotIsToppingUp: Bool
        public let snapshotIsDraining: Bool
        /// Set only on the pass that let the latch go.
        public let release: Release?
    }

    /// The highest level seen since the latch was armed; nil while it is not.
    private var peak: Int?
    /// When the current unbroken run of outward readings began.
    private var outwardSince: Date?

    public var isLatched: Bool { peak != nil }

    public init() {}

    public mutating func reset() {
        peak = nil
        outwardSince = nil
    }

    public mutating func record(
        chargerConnected: Bool,
        batteryLevel: Int,
        limitInForce: Int,
        isCharging: Bool,
        batteryPower: Float?,
        mechanismDrainsToLimitItself: Bool,
        at now: Date
    ) -> Verdict {
        let snapshotIsToppingUp = SystemChargeTopUp.isUnderway(
            batteryLevel: batteryLevel,
            limitInForce: limitInForce,
            isCharging: isCharging,
            batteryPower: batteryPower,
            mechanismDrainsToLimitItself: mechanismDrainsToLimitItself
        )
        let snapshotIsDraining = SystemChargeDrain.isUnderway(
            batteryLevel: batteryLevel,
            limitInForce: limitInForce,
            isCharging: isCharging,
            batteryPower: batteryPower,
            mechanismDrainsToLimitItself: mechanismDrainsToLimitItself
        )

        var release: Release?
        if let currentPeak = peak {
            if !chargerConnected {
                release = .chargerUnplugged
            } else if batteryLevel <= limitInForce {
                release = .reachedLimit
            } else if batteryLevel <= currentPeak - Self.releaseBelowPeak {
                release = .droppedBelowPeak
            } else if ChargeDirection.flow(isCharging: isCharging, batteryPower: batteryPower) == .outOfTheBattery {
                let since = outwardSince ?? now
                outwardSince = since
                if now.timeIntervalSince(since) >= Self.releaseAfterOutwardFlow {
                    release = .sustainedOutwardFlow
                }
            } else {
                // Any reading that is not charge leaving the battery breaks the run.
                outwardSince = nil
            }

            if release == nil, mechanismDrainsToLimitItself {
                peak = max(currentPeak, batteryLevel)
                return Verdict(
                    isToppingUp: true,
                    isDraining: false,
                    snapshotIsToppingUp: snapshotIsToppingUp,
                    snapshotIsDraining: snapshotIsDraining,
                    release: release
                )
            }
            reset()
        } else if chargerConnected, snapshotIsToppingUp, Self.armsTheLatch(batteryLevel: batteryLevel, batteryPower: batteryPower) {
            peak = batteryLevel
            outwardSince = nil
        }

        return Verdict(
            isToppingUp: snapshotIsToppingUp,
            isDraining: snapshotIsDraining,
            snapshotIsToppingUp: snapshotIsToppingUp,
            snapshotIsDraining: snapshotIsDraining,
            release: release
        )
    }

    /// Whether a reading the snapshot already calls a top-up is good enough to hold on to.
    ///
    /// Only the two genuine shapes: the SMC itself measuring charge going in, or the battery
    /// resting at full — the plateau `SystemChargeTopUp` recognises. Not IOKit's `isCharging`
    /// on its own, inside the resting band or with no SMC reading at all: that is exactly the
    /// reading that lags 43 seconds into a drain when the limit is lowered under a charging
    /// battery (measured 2026-09-16), and latching it would hold "macOS is calibrating the battery"
    /// over two minutes of a drain the user had just asked for. Such a reading still labels its
    /// own pass, as it always did; it just does not outlive it.
    private static func armsTheLatch(batteryLevel: Int, batteryPower: Float?) -> Bool {
        guard let batteryPower else { return false }
        if batteryPower < -ChargeDirection.restingThreshold { return true }
        return batteryLevel >= 100 && batteryPower <= ChargeDirection.restingThreshold
    }
}
