//
//  HelperStatusPolling.swift
//  BatFi
//
//  How often the app reads `SMAppService.status`, given what it currently believes about
//  the helper. Pure, so the cadence is a unit-tested decision rather than a constant buried
//  in a timer.
//
//  The read is not free, and it is not the app that pays for it. Every call makes
//  `backgroundtaskmanagementd` re-validate the app bundle, which re-reads the whole main
//  executable from disk. A fixed 1.5s poll for the life of the app was measured on a
//  customer's Mac at ~31 read cycles in 45 seconds, ~107 MiB, and 27 GB read by that daemon
//  since boot — from a battery app, on battery, doing nothing.
//

import Foundation

public enum HelperStatusPolling: Sendable {
    /// While the helper is not known to work. The health policy's reading budgets —
    /// `absentStatusBudget`, `pendingApprovalBudget` — count readings and were sized against
    /// this tick, and the states behind them are each waiting on a status change: Background
    /// Task Management settling, the user answering macOS's consent prompt, or a repair in
    /// Login Items that only shows up as a new status.
    public static let unsettledInterval = Duration.milliseconds(1500)

    /// While the helper works. A backstop only, not the way changes are noticed: a helper
    /// that stops working drops its XPC connection, and that, waking from sleep, and launch
    /// each read the status on the spot. What is left for this to catch is a status that
    /// changes with no other symptom at all, which is not worth a re-validation every few
    /// seconds to hear about promptly.
    public static let healthyInterval = Duration.seconds(10 * 60)

    public static func interval(for health: HelperHealth) -> Duration {
        health.isHealthy ? healthyInterval : unsettledInterval
    }

    /// Whether a wait of `current` should end now that health is `health`.
    ///
    /// Only towards a faster cadence. A helper lost during the long healthy wait would
    /// otherwise sit up to ten minutes with every budget stalled. The opposite is not worth
    /// cutting short — a fast wait ends on its own a moment later — and a change between
    /// two unsettled states must not either: reading early there adds a reading to a budget
    /// that counts them, and corroborates an absence in half the time it is meant to take.
    ///
    /// Ending the wait means starting the faster one, not reading at once. Whatever made
    /// health worse has usually just read the status itself — a dropped connection does —
    /// and a second reading milliseconds later would count towards the same budgets.
    public static func endsWaitEarly(waiting current: Duration, health: HelperHealth) -> Bool {
        interval(for: health) < current
    }
}
