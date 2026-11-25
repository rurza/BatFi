//
//  InitialModeWarningPolicy.swift
//  BatFi
//
//  Whether a charging mode still sitting at `.initial` is worth telling the user about.
//  Pure, so the distinction it draws is provable in a unit test rather than found by
//  someone half way through onboarding.
//

import Foundation

public enum InitialModeWarningPolicy: Sendable {
    /// A mode that never left `.initial` means the app asked for the battery details it needs
    /// and never got them — but only once the app has actually started asking.
    ///
    /// - Parameter onboardingIsUp: onboarding defers `setUpTheApp()` until the helper is in,
    ///   so nothing has requested a charging state yet and `.initial` is simply where the mode
    ///   starts. Warning here tells someone macOS is withholding battery information while
    ///   they are standing on the screen that installs the thing which reads it.
    ///
    /// A healthy helper is not evidence against that: one left registered by a previous
    /// install answers pings perfectly well, which is exactly the case that produced the
    /// spurious notification this guard exists to stop.
    public static func shouldWarn(
        mode: ChargingMode,
        health: HelperHealth,
        onboardingIsUp: Bool
    ) -> Bool {
        guard !onboardingIsUp else { return false }
        guard mode == .initial else { return false }
        return health == .healthy
    }
}
