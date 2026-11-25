//
//  ChargeResumeNudge.swift
//
//
//  Getting a closed charge session re-opened, and deciding when that is worth a write.
//

import Foundation

/// Where to move the enforced limit so powerd re-arms the charger.
public enum ChargeResumeNudge {
    /// How far above the limit in force the nudge goes.
    ///
    /// Three points, because that is enough. Measured 2026-08-19 on 26A5416b: a hold at 74%
    /// under a 75% limit re-armed on a raise to 78%, and the raised value only survived about
    /// **eight seconds** before BatFi's own revert-protection put 75% back — the charger still
    /// re-armed. The stimulus is the *change*, not the value that follows it, so there is no
    /// reason to reach for a larger raise and every reason not to: clearing the limit lands on
    /// Apple's 80% default, which is a number the user did not choose and can see in System
    /// Settings.
    public static let step = 3

    /// The value to write, or nil where no raise is available.
    ///
    /// Nil at 100 rather than writing 100 over 100: an identical value is precisely what was
    /// measured *not* to re-arm anything, so a write there would be a control the user can see
    /// moving for no effect.
    public static func target(forLimitInForce limit: Int) -> Int? {
        let candidate = min(limit + step, 100)
        return candidate > limit ? candidate : nil
    }
}

/// The clock over a run of held readings.
///
/// Shaped like `ChargeHoldDriftMonitor`, and for the same reason: passes arrive on power-source
/// changes rather than on a timer, so counting passes would make the thresholds depend on how
/// busy the Mac is.
public struct ChargeResumeNudgeMonitor: Equatable, Sendable {
    /// How long a hold must last before BatFi writes anything.
    ///
    /// A product decision rather than a measurement. Under a load that outruns the adapter the
    /// charge dips below the limit constantly, and nudging on the first reading would mean
    /// writing to the user's charge limit every few seconds. A minute of idle battery is the
    /// price of not doing that.
    public static let nudgeAfter: TimeInterval = 60

    /// The floor between nudges.
    ///
    /// Success cannot be observed quickly: current appears ~25s after the change, and IOKit —
    /// which is what `isCharging` and `CHNC` come from — lags a further ~17s. A pass landing
    /// inside that window still reads the hold as unchanged, so without this floor a working
    /// nudge would be nudged again on top of itself. Three minutes clears the whole settling
    /// window with room to spare.
    public static let cooldown: TimeInterval = 180

    public enum Response: Equatable, Sendable {
        /// Nothing to do.
        case none
        /// Move the enforced limit, then put the target back once current flows.
        case nudge
    }

    private var holdingSince: Date?
    private var lastNudgedAt: Date?

    public init() {}

    /// Folds one reading in and says whether to nudge.
    public mutating func record(isHolding: Bool, at now: Date) -> Response {
        guard isHolding else {
            // One clean reading ends the run, including the cooldown: the fault is a steady
            // state, so a run that breaks was either fixed or was never one. Keeping the
            // cooldown across a break would suppress the nudge on a genuinely new hold.
            holdingSince = nil
            lastNudgedAt = nil
            return .none
        }
        guard let start = holdingSince else {
            holdingSince = now
            return .none
        }
        guard now.timeIntervalSince(start) >= Self.nudgeAfter else { return .none }
        if let lastNudgedAt, now.timeIntervalSince(lastNudgedAt) < Self.cooldown { return .none }
        lastNudgedAt = now
        return .nudge
    }
}
