//
//  HelperHealthPolicy.swift
//  BatFi
//
//  Decides what to do about helper health. Pure: no XPC, no I/O, no clock of its own, so
//  the rule that matters most here — the mutating recovery runs at most once — is provable
//  in a unit test rather than owed as a hardware check.
//

import Foundation

public struct HelperHealthPolicy: Sendable {
    public enum Event: Sendable, Equatable {
        case statusObserved(HelperServiceStatus)
        case pingSucceeded
        case pingFailed
        /// The one-shot unregister/register cycle finished. `error` is nil on success.
        case retryFinished(error: String?)
        /// Who the reachable helper turned out to be. Only ever follows `.verifyIdentity`,
        /// and always follows it — the caller reports `.undetermined` rather than staying
        /// silent, because silence here would strand the policy short of a verdict.
        case identityChecked(HelperOwnership)
        /// The one-shot take-ownership cycle finished. `error` is nil on success.
        case takeoverFinished(error: String?)
    }

    public enum Action: Sendable, Equatable {
        case verifyWithPing
        /// Read the running helper's code signature and report who it is. Local, cheap and
        /// non-mutating, so it is safe to make a precondition of believing in the helper.
        case verifyIdentity
        case installHelper
        /// Unregister then re-register. Mutates BTM state; emitted at most once per launch.
        case retryRegistrationOnce
        /// Stop the other copy's helper, then unregister and register so the Background
        /// Task Management record names *this* bundle. Mutates BTM state and can cost the
        /// user an approval; emitted at most once per launch.
        case takeOwnership(HelperOwnershipConflict)
        case publish(HelperHealth)
        case showGuidance
        case scheduleProbe(Duration)
    }

    public static let firstProbeDelay = Duration.seconds(5)
    public static let maxProbeDelay = Duration.seconds(60)

    /// Failed pings required *after* a re-registration reported success before the record is
    /// declared beyond this app's reach.
    ///
    /// More than one, because a register that genuinely worked is not always answerable on
    /// the first try: launchd throttles a service that has just died on it — "Service only
    /// ran for 0 seconds. Pushing respawn out by 10 seconds" — so the first probe after a
    /// repair can land inside a window where even a perfectly good record cannot spawn.
    /// Two failures span that window at the ping timeout the app uses, which is the point:
    /// the state this leads to tells the user to go and fix something by hand, and saying
    /// that to someone whose helper was about to start on its own is its own bug.
    public static let postRegistrationProbeBudget = 2

    public private(set) var health: HelperHealth = .unknown

    /// Consecutive failures since the last success or re-registration. A lone failure is
    /// treated as transient — XPC calls die for reasons that have nothing to do with the
    /// helper being wedged — so nothing mutating happens until a second one confirms it.
    private var consecutivePingFailures = 0
    /// Once per launch, deliberately. Repeated re-registration is the behaviour most
    /// plausibly associated with wedging the record this whole type exists to detect.
    private var hasRetriedRegistration = false
    /// Also once per launch, and for a sharper reason: two copies of BatFi running at the
    /// same time each see the other's helper as foreign. Unbounded takeovers would have
    /// them trade the record back and forth for as long as both stay open. Bounded, the
    /// exchange stops after one round and the second copy says so instead.
    private var hasTakenOwnership = false
    /// Whether the currently reachable helper has been identified since the last event that
    /// could have replaced it. Reset by anything that re-registers or restarts the daemon.
    private var hasVerifiedIdentity = false
    /// The conflict the takeover was asked to resolve. Kept so that a *failed* takeover can
    /// still be reported as what it is — someone else's helper — rather than collapsing
    /// into the generic install failure, which would send the user to Login Items to fix a
    /// registration that is working exactly as macOS intends.
    private var lastConflict: HelperOwnershipConflict?
    /// The failure the user has already been told about. Distinct from `health`, which also
    /// carries states published to suppress belief rather than to report to anyone.
    private var announcedHealth: HelperHealth?
    private var nextProbeDelay = HelperHealthPolicy.firstProbeDelay
    /// The status stream repeats every 1.5s by design. Only transitions carry information —
    /// and in the failure this type exists for, the repeated value is `.enabled`, so acting
    /// on every repeat would ping continuously and make the probe backoff meaningless.
    private var lastObservedStatus: HelperServiceStatus?

    public init() {}

    public mutating func handle(_ event: Event) -> [Action] {
        switch event {
        case let .statusObserved(status):
            return handleStatus(status)
        case .pingSucceeded:
            consecutivePingFailures = 0
            nextProbeDelay = Self.firstProbeDelay
            // Reachable is necessary but not sufficient. A helper belonging to another copy
            // of the app answers a ping exactly as well as our own — it *is* a genuine,
            // correctly signed BatFi helper — so believing this one before knowing whose it
            // is would report `.healthy` for the very state this check exists to catch.
            // The check is a local code-signature read, not another round trip, so making
            // it a precondition costs nothing that could hang.
            guard hasVerifiedIdentity else { return [.verifyIdentity] }
            return publishing(.healthy)
        case .pingFailed:
            return handlePingFailure()
        case let .retryFinished(error):
            guard let error else {
                // The re-registration itself worked; whether it helped is a question only a
                // ping can answer — and `register()` returning cleanly is not evidence that
                // it did, because it returns cleanly over a record it merely re-found.
                //
                // Reset rather than seeded. The failures banked before the repair say
                // nothing about the state after it, and counting them towards the verdict
                // would spend most of the post-registration budget before launchd has even
                // been given the chance to spawn.
                consecutivePingFailures = 0
                // A re-registration can change which binary launchd starts, which is the
                // whole point of it. Whatever was established about the previous process
                // says nothing about the next one.
                hasVerifiedIdentity = false
                return [.verifyWithPing]
            }
            return concluding(.degraded(.installFailed(error)))
        case let .identityChecked(ownership):
            return handleIdentity(ownership)
        case let .takeoverFinished(error):
            guard let error else {
                // Whether it worked is a question for the next identity check, not for the
                // absence of an error: `register()` returns cleanly from a copy that did
                // not get the record, which is the defect this whole path exists for.
                hasVerifiedIdentity = false
                consecutivePingFailures = 0
                return [.verifyWithPing]
            }
            guard let lastConflict else { return concluding(.degraded(.installFailed(error))) }
            return concluding(.degraded(.foreignHelper(lastConflict)))
        }
    }

    private mutating func handleIdentity(_ ownership: HelperOwnership) -> [Action] {
        switch ownership {
        case .ours:
            hasVerifiedIdentity = true
            nextProbeDelay = Self.firstProbeDelay
            return publishing(.healthy)
        case .undetermined:
            // No evidence either way. Treated as our own on purpose: the recovery for a
            // conflict costs the user a System Settings approval and takes the helper down
            // in the meantime, and running that on a failed *inspection* would punish every
            // machine where the signature read is unavailable for reasons of its own. The
            // reachability path still covers a helper that is genuinely broken.
            hasVerifiedIdentity = true
            nextProbeDelay = Self.firstProbeDelay
            return publishing(.healthy)
        case let .foreign(conflict):
            guard !hasTakenOwnership else {
                // The one attempt is spent and the helper is still someone else's — which
                // in practice means the other copy is running and re-registering too.
                // Stop, and let the guidance name it, because the fix from here is the
                // user's: quit or delete the copy they do not want.
                return concluding(.degraded(.foreignHelper(conflict)))
            }
            hasTakenOwnership = true
            lastConflict = conflict
            return publishing(.degraded(.foreignHelper(conflict))) + [.takeOwnership(conflict)]
        }
    }

    private mutating func handleStatus(_ status: HelperServiceStatus) -> [Action] {
        guard status != lastObservedStatus else { return [] }
        lastObservedStatus = status

        switch status {
        case .enabled:
            // Never conclusive on its own: a wedged record reports `.enabled` forever.
            return health.isHealthy ? [] : [.verifyWithPing]
        case .notRegistered:
            // The record is gone, which is the one transition that can undo
            // `.staleRegistrationNeedsUserReset`: it is what the user's toggle produces, and
            // installing over it is what mints a record with a constraint that resolves.
            //
            // So the install that follows is given a full budget rather than inheriting the
            // failures banked against the record it replaces. Those were the old record's,
            // and holding them against a new one would report the repair as broken while it
            // was still starting.
            consecutivePingFailures = 0
            hasVerifiedIdentity = false
            return publishing(.degraded(.notRegistered)) + [.installHelper]
        case .requiresApproval:
            // Only the user can clear this, so re-registering would just churn the record.
            return concluding(.degraded(.requiresApproval), scheduleProbe: false)
        case .notFound:
            return concluding(.degraded(.notRegistered), scheduleProbe: false)
        }
    }

    private mutating func handlePingFailure() -> [Action] {
        // A failed ping means the process that was identified is not the one answering now
        // — it may have exited, been replaced, or never have been there. Whoever answers
        // next has to be identified again.
        hasVerifiedIdentity = false
        consecutivePingFailures += 1

        // Past the one re-registration, and it did not help. Everything from here is about
        // establishing that as a fact rather than retrying into it: the record cannot be
        // repaired from inside this process, so the only useful output is guidance naming
        // the one thing that does repair it.
        // `hasTakenOwnership` counts here as much as `hasRetriedRegistration`, because a
        // takeover *is* an unregister/register — it just reached that point down a different
        // road. Reading only the retry flag let one launch spend both: the takeover
        // re-registered, the helper still did not answer, and the unreachable path then
        // re-registered a second time as though nothing had been tried. That is precisely
        // the churn the once-per-launch rule exists to prevent.
        if hasRetriedRegistration || hasTakenOwnership {
            guard consecutivePingFailures >= Self.postRegistrationProbeBudget else {
                // Published, not concluded. Downstream has to stop trusting the helper
                // immediately, since the charge limit must not be driven through a daemon
                // that is not answering, but the user is told nothing until the verdict is
                // in.
                return publishing(.degraded(.registeredButUnreachable)) + [.verifyWithPing]
            }
            // A conflict that was already identified outranks the generic verdict, and the
            // difference is the whole value of the alert. `staleRegistrationNeedsUserReset`
            // tells the user a deleted copy left a record behind and to toggle Login Items.
            // When another copy is sitting right there, holding the registration, that
            // account is simply false and the remedy it names fixes nothing: what resolves
            // it is having one copy, and only the conflict knows where the other one is.
            if let lastConflict {
                return concluding(.degraded(.foreignHelper(lastConflict)))
            }
            return concluding(.degraded(.staleRegistrationNeedsUserReset))
        }

        guard consecutivePingFailures >= 2 else { return [.verifyWithPing] }
        hasRetriedRegistration = true
        consecutivePingFailures = 0
        return [.retryRegistrationOnce]
    }

    /// Publishes a settled failure. Guidance is emitted only on entering the state, so the
    /// repeating probe does not re-nag, and probing continues so that a repair the app
    /// cannot make itself — the user toggling Login Items — is noticed without a relaunch.
    ///
    /// "Entering the state" is tracked separately from the published value, and not derived
    /// from it. Publishing is also how the policy withholds belief while it attempts an
    /// automatic recovery — a foreign helper is published as degraded *before* the takeover
    /// runs, so that nothing downstream drives charging through somebody else's daemon in
    /// the meantime. Reading "already published" as "already announced" therefore silenced
    /// the guidance for the one failure the user cannot diagnose alone: the recovery would
    /// fail, the conclusion would match the value published a moment earlier, and the alert
    /// naming the other copy would never appear.
    private mutating func concluding(_ newHealth: HelperHealth, scheduleProbe: Bool = true) -> [Action] {
        var actions = publishing(newHealth)
        if announcedHealth != newHealth {
            announcedHealth = newHealth
            actions.append(.showGuidance)
        }
        if scheduleProbe {
            actions.append(.scheduleProbe(nextProbeDelay))
            nextProbeDelay = min(nextProbeDelay * 2, Self.maxProbeDelay)
        }
        return actions
    }

    private mutating func publishing(_ newHealth: HelperHealth) -> [Action] {
        health = newHealth
        // Recovering clears the record of what was announced, so that a breakage which
        // comes back after a good spell is reported again rather than swallowed as a repeat.
        if newHealth.isHealthy {
            announcedHealth = nil
        }
        return [.publish(newHealth)]
    }
}
