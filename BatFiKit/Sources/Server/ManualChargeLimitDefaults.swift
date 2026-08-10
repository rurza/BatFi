//
//  ManualChargeLimitDefaults.swift
//  Helper
//
//  The mechanism that expresses a charge limit below 80% on macOS 26.4+ / 27.
//
//  Apple's 80% floor is **client-side validation inside PowerUI.framework**, which loads into
//  the calling process. `setMCLLimit:` checks the requested value against
//  `availableChargeLimits` ([80, 85, 90, 95, 100]) and refuses anything else with
//  `PowerUISmartChargingErrorDomain` code 4 — measured on a Mac15,8, macOS 27.0 (26A5388g),
//  refusing 75 even while 71 was already in force, and refusing it for a root caller too. No
//  client state makes that API accept a sub-80 number.
//
//  But `setMCLLimit:` is only one way to reach the daemon that actually applies limits.
//  `/usr/libexec/PowerUIAgent` runs as root, watches the Darwin notification
//  `com.apple.smartcharging.defaultschanged`, and on receiving it re-reads the preference
//  domain below. It then registers a `ChargeCtrlPolicy` carrying `soclimit`, which powerd
//  serialises into `/Library/Preferences/com.apple.powerd.charging.plist` and the firmware
//  enforces. That path has **no 80% floor** — measured holding 72% with
//  `pmset` reporting `AC attached; not charging`.
//
//  So the limit is requested in the agent's own terms rather than through the client library
//  that would refuse it. This is undocumented private state, so everything here is written
//  defensively: success is confirmed against powerd's own policy rather than by reading back
//  the preference we just wrote, and `release()` removes only what BatFi put there.
//
//  **`CurrentUser` must resolve to root.** PowerUIAgent runs as root and reads root's own
//  preference domain, which is why these writes belong in the helper and would silently do
//  nothing from the app.
//

import Foundation
import IOKit.ps
import os

enum ManualChargeLimitError: Error {
    /// Preferences were written and the notification posted, but powerd never adopted a
    /// matching policy. Treated as a failure rather than assumed-good, because the
    /// preference reading back correctly proves only that we wrote it.
    case notAdopted
    /// The helper is not running as root, so `CurrentUser` is not the user PowerUIAgent reads.
    case notRoot
}

/// Writes the charge limit into the preference domain PowerUIAgent reads, and confirms the
/// result against the policy powerd actually holds.
actor ManualChargeLimitDefaults {
    static let shared = ManualChargeLimitDefaults()

    private let logger = Logger(subsystem: "software.micropixels.BatFi", category: "ManualChargeLimit")

    /// Apple's domain. The two keys are Swift small-string literals in the binaries that use
    /// them, so they do not appear in `strings` output — they were recovered by decoding
    /// `movz`/`movk` immediates.
    private let domain = "com.apple.smartcharging.topoffprotection" as CFString
    private let limitKey = "mclLimitValue" as CFString
    private let stateKey = "MCLFeatureState" as CFString
    private let changedNotification = "com.apple.smartcharging.defaultschanged"

    /// Root's own domain, which is what PowerUIAgent reads. Any other scope is written
    /// successfully and then ignored, which is the most misleading possible failure.
    private let user = kCFPreferencesCurrentUser
    private let host = kCFPreferencesCurrentHost

    private let powerdPolicyPath = "/Library/Preferences/com.apple.powerd.charging.plist"

    /// The limit powerd is **enforcing**, not the one we asked for.
    ///
    /// This is the honest check and the only one worth making: the preference is our input,
    /// the policy is the system's answer. Callers use it to notice that a limit stopped
    /// holding — powerd retires the policy whenever Apple's charge limit changes underneath.
    func currentLimit() -> Int? {
        guard let data = FileManager.default.contents(atPath: powerdPolicyPath),
              let top = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let archived = top["policies"] as? Data,
              let archive = try? PropertyListSerialization.propertyList(
                  from: archived, options: [], format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any]
        else { return nil }
        // The archive is an NSKeyedArchiver graph whose `reason` is a UID reference that is
        // awkward to resolve through PropertyListSerialization. Matching on the presence of
        // `soclimit` is sufficient: powerd holds a single charge-limit policy at a time.
        for object in objects {
            if let policy = object as? [String: Any], let soclimit = policy["soclimit"] as? Int {
                return soclimit
            }
        }
        return nil
    }

    /// The limit an `apply` is currently waiting on, if any.
    ///
    /// **Actors are reentrant across suspension points**, so `await`ing inside the polling
    /// loop below hands the actor to the next caller rather than making it queue. Without
    /// this guard, `applyChargeLimit` running on several tasks at once produced four
    /// overlapping applies that each rewrote the keys and re-posted the notification while
    /// PowerUIAgent was still settling the first — measured, with all four then failing at
    /// the same millisecond. Actor isolation alone does not serialise this.
    private var applyInFlight: Int?

    /// Whether `limit` is as applied as it can currently be.
    ///
    /// powerd enforcing it is the strong answer and the only one that means charging is
    /// actually being held. But while unplugged there is no policy to enforce anything and
    /// nothing is charging, so a written preference is the whole of what "applied" can mean —
    /// and reading that as drift is what made the caller re-apply on every status pass, once
    /// every three seconds, for as long as the Mac stayed on battery.
    ///
    /// Deliberately separate from `currentLimit()`, which stays a report of what powerd holds
    /// and nothing else. Diagnostics and the settings pane need that distinction; only the
    /// re-assertion check wants this softer question.
    func isSatisfied(_ limit: Int) -> Bool {
        if currentLimit() == limit { return true }
        guard !isOnAdapterPower() else { return false }
        return CFPreferencesCopyValue(limitKey, domain, user, host) as? Int == limit
    }

    /// Puts a limit in force through PowerUIAgent.
    ///
    /// `MCLFeatureState` switches the feature on; `mclLimitValue` carries the number. Both are
    /// written before the notification, because the notification is what makes the agent read
    /// them — posting first simply loses the update.
    func apply(limit: Int) async throws {
        guard geteuid() == 0 else { throw ManualChargeLimitError.notRoot }
        guard currentLimit() != limit else { return }
        // The same request is already being waited on. Joining it rather than repeating it:
        // a second write of identical values buys nothing and the re-posted notification is
        // actively harmful while the agent is mid-settle. The caller re-checks on its next
        // pass anyway, so reporting the in-flight attempt as this one's outcome cannot strand
        // a limit that never landed.
        guard applyInFlight != limit else { return }

        // Already written, and on battery nothing will adopt it — so there is nothing left to
        // do until the adapter returns. Without this the caller's drift check never settles:
        // it compares against powerd's `soclimit`, which while unplugged is whatever was last
        // in force and can never become the target, so every status pass reads as drift and
        // re-applies. Measured rewriting the keys and re-posting the notification once every
        // three seconds, indefinitely.
        if !isOnAdapterPower(), CFPreferencesCopyValue(limitKey, domain, user, host) as? Int == limit {
            return
        }

        applyInFlight = limit
        defer { applyInFlight = nil }

        writeRequest(limit)

        // **powerd keeps a charge policy only while on the adapter.** Unplugged, the policies
        // array is empty, so waiting for adoption can only ever time out — and the caller
        // treats that timeout as a refusal: it writes 80 into the user's own System Settings
        // limit and the pane then says limits below 80% cannot be applied *on this Mac*, which
        // is a claim about the hardware when the only true thing is that the charger is out.
        // Measured doing exactly that, once per status pass, 45s at a time.
        //
        // The preference stays written, so PowerUIAgent picks it up when the adapter returns.
        // Nothing is being charged meanwhile, so there is no limit left unenforced.
        guard isOnAdapterPower() else {
            logger.notice("Charge limit \(limit, privacy: .public)% written; on battery, so powerd will adopt it when the adapter is connected")
            return
        }

        // With Apple's charge limit switched off entirely, nothing is there to honour a
        // policy. `enableMCL:` takes no value, so unlike `setMCLLimit:` it cannot make powerd
        // rewrite a number and cannot start a write-fight. Gated on the feature actually
        // being off, so a settled machine never touches it.
        if await !PowerUICharging.shared.isMCLCurrentlyEnabled {
            await PowerUICharging.shared.enableMCL()
            postChangeNotification()
        }

        // The agent re-reads, registers the policy and powerd serialises it — all
        // asynchronously, and **slowly**. Written once, then only read: re-writing while
        // waiting is what the reentrancy guard above exists to prevent.
        //
        // The budget is deliberately far larger than the write takes. Measured on macOS 27.0
        // (26A5388g): a preference write whose adoption had not appeared after six seconds
        // landed anyway, with powerd's plist rewritten roughly half a minute later. Every
        // earlier "did not adopt" verdict in this investigation was that impatience, not a
        // refusal — and the cost of getting it wrong is not a slow apply, it is the caller
        // falling back to `setMCLLimit(80)` and **overwriting an adoption that was still in
        // flight**. Waiting is cheap; giving up early actively destroys the request.
        //
        // Only ever paid when the limit is not already in force: the `currentLimit()` guard
        // above returns immediately on the once-a-minute re-assertion of a settled limit.
        if await powerdAdopts(limit, within: .seconds(45)) {
            logger.notice("Charge limit \(limit, privacy: .public)% adopted by powerd")
            return
        }

        logger.error("Charge limit \(limit, privacy: .public)% was written but powerd did not adopt it")
        throw ManualChargeLimitError.notAdopted
    }

    /// Writes both keys and tells PowerUIAgent to re-read them.
    private func writeRequest(_ limit: Int) {
        CFPreferencesSetValue(limitKey, limit as CFNumber, domain, user, host)
        CFPreferencesSetValue(stateKey, 1 as CFNumber, domain, user, host)
        CFPreferencesSynchronize(domain, user, host)
        postChangeNotification()
    }

    /// Polls powerd's own policy, which is the only evidence that a limit is in force, and
    /// **re-asserts the request if it goes missing**.
    ///
    /// Writing once and waiting is too fragile to be correct. Adoption can take tens of
    /// seconds, and over that window plenty can remove the request: a `release()` from a
    /// teardown path, or another `apply` for a different value while the user drags the
    /// slider. Measured exactly that — a release landed sixteen seconds into the wait, the
    /// preference was gone, and this then waited out its whole budget for an adoption that
    /// could no longer happen. The caller read that as a refusal and raised the limit to 80,
    /// so lowering the limit from 65% to 60% *started charging*.
    ///
    /// Re-asserting is cheap and idempotent, and only happens when the request has actually
    /// been lost, so a settled apply still writes exactly once.
    ///
    /// Deliberately not checked with `getMCLLimitWithError:`. That reports the *preference*
    /// back — it read 62 while powerd held 80 and the battery charged straight past it — so it
    /// can confirm only that we wrote something, never that anything is enforcing it.
    private func powerdAdopts(_ limit: Int, within duration: Duration) async -> Bool {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            if currentLimit() == limit { return true }
            if CFPreferencesCopyValue(limitKey, domain, user, host) as? Int != limit {
                logger.notice("Charge limit request for \(limit, privacy: .public)% went missing while waiting; writing it again")
                writeRequest(limit)
            }
        }
        return false
    }

    /// Removes BatFi's request, so the limit cannot outlive BatFi.
    ///
    /// This is persistent root-owned state: a sub-80 value left behind would go on capping the
    /// Mac with nothing installed that still knows why. Clearing both keys and posting the
    /// notification is what retires the policy.
    func release() {
        guard geteuid() == 0 else { return }
        // Nothing of ours to undo. Checked against the preference rather than the policy,
        // because a limit at or above PowerUI's own floor is one the user or the system could
        // equally have set through System Settings, and removing that would be BatFi editing a
        // setting it does not own.
        guard CFPreferencesCopyValue(limitKey, domain, user, host) != nil else { return }

        CFPreferencesSetValue(limitKey, nil, domain, user, host)
        CFPreferencesSetValue(stateKey, nil, domain, user, host)
        CFPreferencesSynchronize(domain, user, host)
        postChangeNotification()
        logger.notice("Charge limit request cleared")
    }

    /// Whether the Mac is running on the power adapter.
    ///
    /// Optimistic when the power source cannot be read, because the two failure directions are
    /// not equal: waiting needlessly costs a slow apply, while skipping the wait wrongly would
    /// report a limit as in force without ever confirming it.
    private func isOnAdapterPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue()
        else { return true }
        return (providing as String) == kIOPMACPowerKey
    }

    private func postChangeNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(changedNotification as CFString),
            nil, nil, true
        )
    }
}
