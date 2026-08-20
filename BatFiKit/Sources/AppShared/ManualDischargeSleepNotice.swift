//
//  ManualDischargeSleepNotice.swift
//
//
//  Whether to tell the user that "Run on Battery" will stop this Mac sleeping at all.
//

import Foundation

public enum ManualDischargeSleepNotice {
    /// - Parameters:
    ///   - backendOwnsDischarge: `ChargeBackend.dischargesToLimitItself`. Where macOS drains to
    ///     the limit itself, a manual discharge is the only thing left driving the SMC, and it
    ///     is the only case that disables sleep — so it is the only case worth disclosing.
    ///   - userSuppressed: the alert's own checkbox.
    public static func shouldShow(backendOwnsDischarge: Bool, userSuppressed: Bool) -> Bool {
        backendOwnsDischarge && !userSuppressed
    }
}
