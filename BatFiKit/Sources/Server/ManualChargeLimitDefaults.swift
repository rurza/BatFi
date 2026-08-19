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
import Shared

enum ManualChargeLimitError: Error {
    /// Preferences were written and the notification posted, but powerd never adopted a
    /// matching policy. Treated as a failure rather than assumed-good, because the
    /// preference reading back correctly proves only that we wrote it.
    case notAdopted
    /// The helper is not running as root, so `CurrentUser` is not the user PowerUIAgent reads.
    case notRoot
    /// A newer request for a different limit arrived while this one was waiting. Not a
    /// failure of the mechanism — this request simply stopped being the answer, and the
    /// newer one is still running. Distinguished from `notAdopted` because the two want
    /// opposite handling: a refusal is worth falling back over, being superseded is not.
    case superseded
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

    /// Identity of the newest request the mechanism has seen, handed out in order.
    ///
    /// `applyInFlight` alone cannot answer "has a newer request taken over", and that is the
    /// question the polling loop has to ask before it writes. Two different limits both pass
    /// the guard above — that is what it is for, a slider drag is a stream of different
    /// values — and each then sees the other's write as its own request going missing and
    /// puts its own back, twice a second, for as long as 45 seconds. Captured live on
    /// 26A5416b with 65% and 70% fighting; powerd ended up enforcing the stale 65% nine
    /// seconds after it had adopted 70%.
    ///
    /// Identity rather than a value, and monotonic rather than a flag, because being
    /// superseded has to **outlive the request that superseded it**: the newer request
    /// finishes and clears `applyInFlight`, and an older one comparing against "is anything
    /// in flight" would find the field empty and resume fighting a limit that is already in
    /// force.
    private var latestRequestID: ChargeLimitRequestID = 0

    /// Whether BatFi is deliberately holding a value other than the user's target right now.
    ///
    /// The nudge below writes a limit the user did not ask for, on purpose, for a few seconds.
    /// Every re-assertion path in this app exists to undo exactly that, and one of them —
    /// `SMCService`'s `isSatisfied` check — reacted in **two seconds** when the nudge was tried
    /// by hand on 26A5416b. It did not matter there, because the change alone re-arms the
    /// charger, but a remedy that races its own protection is one bug away from a write-loop.
    private var nudgeInFlight = false

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
        // BatFi moved the limit itself and is about to move it back. Reporting this as
        // satisfied is what keeps the re-assertion check from undoing the nudge mid-flight.
        if nudgeInFlight { return true }
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
        // Every early return below says why. They are the passes that write nothing, they
        // are the majority — this runs on every status update — and until they were logged
        // a limit that was never applied and a limit that needed no applying left exactly
        // the same trace: none.
        let enforced = currentLimit()
        guard enforced != limit else {
            logger.debug("Charge limit \(limit, privacy: .public)% is already the policy powerd holds; nothing to write")
            return
        }
        // The same request is already being waited on. Joining it rather than repeating it:
        // a second write of identical values buys nothing and the re-posted notification is
        // actively harmful while the agent is mid-settle. The caller re-checks on its next
        // pass anyway, so reporting the in-flight attempt as this one's outcome cannot strand
        // a limit that never landed.
        guard applyInFlight != limit else {
            logger.notice("Charge limit \(limit, privacy: .public)% is already being waited on; joining that request")
            return
        }

        // Already written, and on battery nothing will adopt it — so there is nothing left to
        // do until the adapter returns. Without this the caller's drift check never settles:
        // it compares against powerd's `soclimit`, which while unplugged is whatever was last
        // in force and can never become the target, so every status pass reads as drift and
        // re-applies. Measured rewriting the keys and re-posting the notification once every
        // three seconds, indefinitely.
        if !isOnAdapterPower(), CFPreferencesCopyValue(limitKey, domain, user, host) as? Int == limit {
            logger.notice("Charge limit \(limit, privacy: .public)% is written and the Mac is on battery; leaving it for the adapter's return")
            return
        }

        // Arriving is what makes a request the newest one: it carries the value the user
        // last asked for, and every request still waiting carries a value they have moved
        // away from.
        latestRequestID &+= 1
        let requestID = latestRequestID
        applyInFlight = limit
        // Only if it is still ours. Clearing unconditionally would hand a newer request's
        // slot back on this one's way out, and the identical-value join above would then
        // let a duplicate through.
        defer { if latestRequestID == requestID { applyInFlight = nil } }

        logger.notice("Applying charge limit \(limit, privacy: .public)%; powerd currently holds \(enforced.map(String.init) ?? "no policy", privacy: .public)")
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
        switch await waitForAdoption(of: limit, requestID: requestID, within: .seconds(45)) {
        case .adopted:
            logger.notice("Charge limit \(limit, privacy: .public)% adopted by powerd")
            return
        case .superseded:
            logger.notice("Charge limit \(limit, privacy: .public)% was superseded by a newer request; abandoning it rather than writing it again")
            throw ManualChargeLimitError.superseded
        case .timedOut:
            logger.error("Charge limit \(limit, privacy: .public)% was written but powerd did not adopt it within 45s")
            throw ManualChargeLimitError.notAdopted
        }
    }

    /// Makes powerd re-open a charge session it closed, by moving the enforced value and
    /// putting the target straight back.
    ///
    /// Measured on 26A5416b, 2026-08-19, against a live hold at 74% under a 75% limit:
    /// re-writing the *same* limit does nothing — 75s of it, plus PowerUIAgent's own periodic
    /// re-registrations, left the battery at 0 mA. Raising it by three points re-armed the
    /// charger, and the raised value only had to be in force for about **eight seconds**: the
    /// revert-protection put 75% back after 8s and current appeared anyway, ~25s after the
    /// change. So the stimulus is the change itself, not the value that follows it.
    ///
    /// The target therefore goes back immediately rather than after waiting for current. That
    /// is both faster and safer: while the nudged value is in force it is the limit the machine
    /// would charge to, so the shortest possible window is the one that cannot overshoot. The
    /// same measurement showed restoring mid-charge does not cancel the session — the battery
    /// charged on and stopped at 75%.
    ///
    /// Both writes go through `apply`, so they inherit the reentrancy guard, the supersede
    /// logic and the adoption wait rather than reimplementing them. A nudge that fails to be
    /// adopted still restores: the restore is what protects the user, and skipping it because
    /// the first write timed out would leave a limit they never chose in force.
    func nudgeToResumeCharging(to nudgeValue: Int, restoring target: Int) async throws -> Bool {
        guard geteuid() == 0 else { throw ManualChargeLimitError.notRoot }
        guard nudgeValue != target else { return false }
        guard !nudgeInFlight else {
            logger.notice("A charge-resume nudge is already in flight; not starting another")
            return false
        }
        nudgeInFlight = true
        logger.notice("Nudging the charge limit to \(nudgeValue, privacy: .public)% to re-open the charge session, then restoring \(target, privacy: .public)%")
        do {
            try await apply(limit: nudgeValue)
        } catch {
            // Logged and swallowed. A timeout here does not mean the write was refused — the
            // adoption may still be in flight — and either way the restore below is what has
            // to happen next.
            logger.error("Charge-resume nudge to \(nudgeValue, privacy: .public)% did not confirm: \(error, privacy: .public)")
        }
        // Cleared before the restore, not after: the restore is an ordinary apply of the
        // user's own limit and must be visible to `isSatisfied` as such.
        nudgeInFlight = false
        try await apply(limit: target)
        logger.notice("Charge limit \(target, privacy: .public)% restored after the nudge")
        return true
    }

    /// Writes both keys and tells PowerUIAgent to re-read them.
    private func writeRequest(_ limit: Int) {
        CFPreferencesSetValue(limitKey, limit as CFNumber, domain, user, host)
        CFPreferencesSetValue(stateKey, 1 as CFNumber, domain, user, host)
        CFPreferencesSynchronize(domain, user, host)
        postChangeNotification()
    }

    /// Polls powerd's own policy, which is the only evidence that a limit is in force, and
    /// **re-asserts the request if it goes missing — unless a newer request has taken over**.
    ///
    /// Writing once and waiting is too fragile to be correct. Adoption can take tens of
    /// seconds, and over that window a `release()` from a teardown path can remove the
    /// request. Measured exactly that — a release landed sixteen seconds into the wait, the
    /// preference was gone, and this then waited out its whole budget for an adoption that
    /// could no longer happen. The caller read that as a refusal and raised the limit to 80,
    /// so lowering the limit from 65% to 60% *started charging*.
    ///
    /// The second way a request disappears is **another request replacing it**, and that one
    /// must not be re-asserted. A slider drag produces a stream of different values, each
    /// admitted by the identical-value guard in `apply`, and before `requestID` existed each
    /// read the next one's write as its own going missing and put its own back — twice a
    /// second, each, until one of them timed out. Captured on 26A5416b with 65% and 70%
    /// fighting for five seconds; powerd adopted 70%, then the stale 65% nine seconds later,
    /// and it took a later status pass to undo it. A stale request winning with a *higher*
    /// value is the same bug charging the battery past the limit the user just set.
    ///
    /// Re-asserting is cheap and idempotent, and only happens when the request has actually
    /// been lost and this request is still the current one, so a settled apply still writes
    /// exactly once.
    ///
    /// Deliberately not checked with `getMCLLimitWithError:`. That reports the *preference*
    /// back — it read 62 while powerd held 80 and the battery charged straight past it — so it
    /// can confirm only that we wrote something, never that anything is enforcing it.
    private enum AdoptionOutcome {
        case adopted
        case superseded
        case timedOut
    }

    private func waitForAdoption(
        of limit: Int,
        requestID: ChargeLimitRequestID,
        within duration: Duration
    ) async -> AdoptionOutcome {
        let deadline = ContinuousClock.now + duration
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(500))
            // The decision itself is in `Shared`, where the test target can reach it. It is
            // three lines and it was wrong in a way only a log capture of two live requests
            // revealed, which is exactly the sort of thing that belongs under test.
            let written = CFPreferencesCopyValue(limitKey, domain, user, host) as? Int
            switch ChargeLimitReassertion.step(
                requested: limit,
                requestID: requestID,
                latestRequestID: latestRequestID,
                enforcedLimit: currentLimit(),
                writtenRequest: written
            ) {
            case .adopted:
                return .adopted
            case .superseded:
                return .superseded
            case .rewriteRequest:
                logger.notice("Charge limit request for \(limit, privacy: .public)% went missing while waiting (domain holds \(written.map(String.init) ?? "nothing", privacy: .public)); writing it again")
                writeRequest(limit)
            case .keepWaiting:
                continue
            }
        }
        return .timedOut
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
