//
//  ChargeLimitRaiseWindow.swift
//
//
//  When a raised limit can still make a battery look held below it.
//
//  Under Apple's charge limit a raise takes effect in three steps, each measured: powerd
//  adopts the new `soclimit` up to ~45 s after it is written, current starts ~25 s after
//  that, and IOKit's `IsCharging` follows ~20 s later still. Until the last of them a battery
//  that is about to charge reads as not charging, and the firmware's hold attribution —
//  cached for `ChargeHoldDriftMonitor.attributionInterval` — still names the old limit. The
//  rule in `SystemChargeHold` then calls it "Charging paused by macOS", which is false, and
//  the banner for it was announced: first when the resume of an inhibit waited on adoption
//  alone, and again just after adoption once that was fixed.
//
//  A lowering has the mirror window. powerd goes on enforcing the higher limit for up to
//  ~45 s, and current takes ~25 s more to stop after it adopts the lower one, so a battery
//  above the new limit reads as charging past it: "macOS is charging past the limit", the
//  drift run towards "your charge limit isn't holding" — and for "Inhibit Charging", whose
//  frozen limit is a lowering, both under a pause the user has just been shown. The state
//  the user asked for is shown at once and held through the window; the above-limit states
//  come back once it is over, and are genuine by then.
//
//  This watches powerd's enforced limit and BatFi's applied one across passes and says when
//  each verdict is held back, and when the cached attribution has gone stale. Neither window
//  outlasts `backstop`. Here rather than in `ChargingManager` because `AppCore` has no test
//  target.
//

import Foundation

public struct ChargeLimitRaiseWindow: Sendable {
    /// How long after powerd is seen enforcing a raised or lowered limit its verdicts stay held
    /// back. Covers the ~45 s measured from adoption to IOKit reporting the change, twice.
    public static let settleInterval: TimeInterval = 90

    /// The longest either window holds a verdict back, from the change that opened it: a
    /// powerd that never adopts a value — an off-step one it rounds, say — is not waited on
    /// for good, and the real state shows after it.
    public static let backstop: TimeInterval = 180

    public struct Verdict: Equatable, Sendable {
        /// No "held below the limit" verdict this pass: powerd has not adopted a raise yet
        /// (`SystemChargeHold.isAwaitingAdoption`), or adopted one under `settleInterval` ago.
        public let suppressesHold: Bool
        /// None of the states of a battery above the limit this pass — macOS charging past it,
        /// draining to it, the drift run: the applied limit was lowered and powerd has not
        /// adopted it yet, or adopted it under `settleInterval` ago.
        public let suppressesAboveLimitStates: Bool
        /// powerd's enforced limit is not what it was on the last pass that read one. A hold
        /// attribution read before this is about the old limit.
        public let enforcedLimitChanged: Bool
        /// The limit BatFi applied is not what it was on the last pass. Likewise.
        public let appliedLimitChanged: Bool
    }

    private var lastEnforced: Int?
    private var lastApplied: Int?
    private var raiseAdoptedAt: Date?
    /// Since when powerd has been seen enforcing less than the applied limit.
    private var awaitingRaiseSince: Date?
    /// When the applied limit last went down, while its window is open.
    private var loweredAt: Date?
    /// When powerd was first seen no longer above the lowered limit.
    private var loweringAdoptedAt: Date?

    public init() {}

    /// The limit BatFi applied on the last pass whose apply succeeded, or nil before the first.
    public var lastAppliedLimit: Int? { lastApplied }

    /// Records this pass's readings.
    ///
    /// - Parameters:
    ///   - enforced: powerd's `soclimit`, or nil where there is no policy or none was read.
    ///     Nil does not erase the previous reading: on battery powerd keeps no policy at all,
    ///     and a raise adopted across such a gap is still a raise.
    ///   - applied: the limit BatFi put in force this pass.
    ///   - appliedWasConfirmed: false where the apply failed and `applied` is only the limit
    ///     asked for. Then nothing is learned about the applied limit: it is not remembered,
    ///     and neither a change nor a lowering is reported — a request the mechanism cannot
    ///     express (70 under an 80 floor) would otherwise make the next success read as a raise.
    ///   - changesAwaitPowerd: whether a new limit waits on powerd to take effect — Apple's
    ///     charge limit. Elsewhere a lowering opens no window: the inhibit backends act on it
    ///     with one write, and holding the drift run back after each would only blind it.
    public mutating func record(enforced: Int?, applied: Int, appliedWasConfirmed: Bool = true, changesAwaitPowerd: Bool = true, now: Date) -> Verdict {
        var enforcedChanged = false
        if let enforced {
            if let lastEnforced, lastEnforced != enforced {
                enforcedChanged = true
                if enforced > lastEnforced {
                    raiseAdoptedAt = now
                }
            }
            lastEnforced = enforced
        }
        var appliedChanged = false
        if appliedWasConfirmed {
            if let lastApplied, lastApplied != applied {
                appliedChanged = true
                if applied < lastApplied {
                    loweredAt = changesAwaitPowerd ? now : nil
                    loweringAdoptedAt = nil
                } else {
                    loweredAt = nil
                    loweringAdoptedAt = nil
                    // A new raise is a new adoption to wait for, whatever the last one did.
                    awaitingRaiseSince = nil
                }
            }
            lastApplied = applied
        }

        // The raise.
        let settling = raiseAdoptedAt.map { now.timeIntervalSince($0) < Self.settleInterval } ?? false
        if !settling {
            raiseAdoptedAt = nil
        }
        var awaitingRaise = false
        if SystemChargeHold.isAwaitingAdoption(limitInForce: applied, enforcedLimit: enforced) {
            let since = awaitingRaiseSince ?? now
            awaitingRaiseSince = since
            awaitingRaise = now.timeIntervalSince(since) < Self.backstop
        } else {
            awaitingRaiseSince = nil
        }

        // The lowering.
        var holdingLowering = false
        if let lowered = loweredAt, now.timeIntervalSince(lowered) < Self.backstop {
            if let enforced, enforced > applied {
                holdingLowering = true
            } else {
                let adopted = loweringAdoptedAt ?? now
                loweringAdoptedAt = adopted
                holdingLowering = now.timeIntervalSince(adopted) < Self.settleInterval
            }
        }
        if !holdingLowering {
            loweredAt = nil
            loweringAdoptedAt = nil
        }

        return Verdict(
            suppressesHold: settling || awaitingRaise,
            suppressesAboveLimitStates: holdingLowering,
            enforcedLimitChanged: enforcedChanged,
            appliedLimitChanged: appliedChanged
        )
    }
}
