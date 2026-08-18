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
        /// The user removed the helper on purpose.
        ///
        /// Without this the policy only ever sees the consequence — a helper that stopped
        /// answering — which is the same evidence a wedged record produces, and the recovery
        /// for that is to re-register. A deliberate removal was therefore undone about a
        /// second after it was asked for.
        case removalRequestedByUser
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

    /// Absent status readings required before the app tells the user there is no helper.
    ///
    /// `SMAppService.status` answers from Background Task Management rather than from the
    /// daemon, and the answer is not trustworthy the instant it is asked for. The app asks at
    /// its earliest possible moment — `observeHelperStatus()` yields `service.status`
    /// synchronously, before its first poll — so a launch that outruns BTM read `.notFound`
    /// and, until this budget existed, put a modal on screen offering to install a helper that
    /// was already registered and running. A reading that disagrees with a working helper is
    /// not hypothetical: one was observed publishing this absence while the helper answered a
    /// ping ten seconds later.
    ///
    /// So this is a second opinion, which every other verdict here already required. Three
    /// readings against a stream that ticks every 1.5s is about three seconds of agreement —
    /// sized to the poll interval rather than to any measured settling time, which is not a
    /// number this codebase knows. It must stay above one, or the first reading both
    /// distrusts the helper and reports it, which is the behaviour it replaces.
    public static let absentStatusBudget = 3

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

    /// Pending-approval readings required before the app interrupts the user about one.
    ///
    /// Registering a privileged daemon is what makes macOS post its own consent prompt —
    /// "BatFi.app can run in the background for all users. Do you want to allow this?" — and
    /// `SMAppService.status` reports `.requiresApproval` from the moment the registration
    /// lands, measured 0.6s after `register()`. The prompt is still on screen at that point,
    /// unanswered, offering in one click exactly what this policy's guidance sends the user
    /// to System Settings to do by hand. Announcing there talks over the system and
    /// recommends the longer route.
    ///
    /// Ten readings against a stream that ticks every 1.5s is about fifteen seconds: long
    /// enough for a person to read a notification and click Allow, short enough that a prompt
    /// they dismissed or never saw is still explained while they are looking at the app. Sized
    /// to the poll interval, like `absentStatusBudget`, rather than to any measured settling
    /// time — and it must stay above one, or the reading that arrives while macOS is asking is
    /// the reading that interrupts.
    ///
    /// The verdict itself is *published* on the first reading regardless. The status item's
    /// warning row should be honest immediately, and nothing may be driven through a helper
    /// that is not running; only the interruption waits.
    public static let pendingApprovalBudget = 10

    public private(set) var health: HelperHealth = .unknown

    /// Consecutive absent readings since the last status that reported a record. Counted
    /// rather than acted on, so that an absence which is gone by the next poll costs the user
    /// nothing.
    private var consecutiveAbsentStatuses = 0
    /// Consecutive `.requiresApproval` readings since the last status that was not one.
    /// Counted for the same reason as the absences above, against a different clock: this one
    /// is not waiting for Background Task Management to settle, it is waiting for a person to
    /// answer the prompt macOS has just put in front of them.
    private var consecutivePendingApprovals = 0
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
    /// Set while the absence of a helper is the outcome the user asked for. Cleared by a
    /// status that reports a record again, so the suppression covers the removal rather than
    /// the rest of the launch — a helper installed afterwards can wedge like any other, and
    /// the one recovery this policy is allowed has to still be there for it.
    private var wasRemovedByUser = false
    /// The conflict the takeover was asked to resolve. Kept so that a *failed* takeover can
    /// still be reported as what it is — someone else's helper — rather than collapsing
    /// into the generic install failure, which would send the user to Login Items to fix a
    /// registration that is working exactly as macOS intends.
    private var lastConflict: HelperOwnershipConflict?
    /// The failure the user has already been told about. Distinct from `health`, which also
    /// carries states published to suppress belief rather than to report to anyone.
    private var announcedHealth: HelperHealth?
    private var nextProbeDelay = HelperHealthPolicy.firstProbeDelay
    /// The status stream repeats every 1.5s by design, and for `.enabled` only transitions
    /// carry information — in the failure this type exists for the repeated value *is*
    /// `.enabled`, so acting on every repeat would ping continuously and make the probe
    /// backoff meaningless.
    ///
    /// The absence branch is the exception, and it needs the repeats: agreement across
    /// successive readings is the whole of its evidence, and the readings are identical by
    /// nature. `consecutiveAbsentStatuses` is what bounds the repetition there instead.
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
        case .removalRequestedByUser:
            // Published rather than concluded. Downstream has to stop trusting the helper at
            // once, but the guidance for an absent one offers to install it, which is the
            // opposite of what was just asked for.
            wasRemovedByUser = true
            consecutivePingFailures = 0
            hasVerifiedIdentity = false
            return publishing(.degraded(.notRegistered))
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
        // Tracked per branch rather than discarded up front, because the absence below has to
        // count the repeats in order to require agreement across them.
        let isRepeat = status == lastObservedStatus
        lastObservedStatus = status

        switch status {
        case .enabled:
            consecutiveAbsentStatuses = 0
            consecutivePendingApprovals = 0
            // A record exists again, so whatever the user removed has been replaced — by this
            // app's own install, or by their hand in Login Items. The suppression covered the
            // removal, not the rest of the launch.
            wasRemovedByUser = false
            guard !isRepeat else { return [] }
            // Never conclusive on its own: a wedged record reports `.enabled` forever.
            return health.isHealthy ? [] : [.verifyWithPing]
        case .notRegistered, .notFound:
            // Both mean the same thing to a user — there is no helper — and neither installs
            // one from here. Registering a privileged daemon makes macOS post a
            // background-item notification and, often, demand an approval; doing that
            // unasked, seconds after launch, is indistinguishable from the app misbehaving.
            // The guidance below carries a button that installs, so the prompt arrives as
            // the answer to a click rather than ahead of one.
            //
            // The counters are still cleared, because whatever was banked belonged to a
            // record that no longer exists, and holding it against the next one would report
            // a fresh install as broken while it was still starting.
            //
            // No probe: there is nothing registered to ping, and the status stream already
            // polls, so a record appearing — by this app's button or by the user's own hand
            // in Login Items — is noticed without one.
            consecutivePingFailures = 0
            hasVerifiedIdentity = false
            consecutivePendingApprovals = 0
            consecutiveAbsentStatuses += 1
            switch consecutiveAbsentStatuses {
            case 1:
                // Distrusted at once, reported only once corroborated. Nothing may be driven
                // through a daemon that may not be there, but one reading of a Background
                // Task Management state that has not necessarily loaded yet is not something
                // to put a modal on screen about. See `absentStatusBudget`.
                return publishing(.degraded(.notRegistered))
            case Self.absentStatusBudget:
                // Corroborated, but not news. The alert this verdict carries offers to install
                // a helper, and the reason there is none is that the user removed it moments
                // ago — the absence is the outcome they asked for, not a fault to report.
                guard !wasRemovedByUser else { return publishing(.degraded(.notRegistered)) }
                return concluding(.degraded(.notRegistered), scheduleProbe: false)
            default:
                // Neither corroborated nor contradicted yet, and already distrusted. The
                // stream's next tick is what moves this along.
                return []
            }
        case .requiresApproval:
            consecutiveAbsentStatuses = 0
            // Counted rather than gated on `isRepeat`, for the same reason the absence above
            // is: agreement across readings is the whole mechanism, and the repeats are what
            // it is counting.
            consecutivePendingApprovals += 1
            switch consecutivePendingApprovals {
            case 1:
                // Published, not announced. macOS is asking the user this exact second, and
                // it offers the approval in one click; an alert here recommends the same
                // thing the long way round and covers whatever the user was looking at.
                return publishing(.degraded(.requiresApproval))
            case Self.pendingApprovalBudget:
                // The prompt has gone unanswered — dismissed, missed, or never posted because
                // macOS had already asked once. System Settings is the only route left, and
                // the app is the only thing that will mention it. No probe and no
                // re-registration: only the user can clear this, so re-registering would just
                // churn the record.
                return concluding(.degraded(.requiresApproval), scheduleProbe: false)
            default:
                return []
            }
        }
    }

    private mutating func handlePingFailure() -> [Action] {
        // A failed ping means the process that was identified is not the one answering now
        // — it may have exited, been replaced, or never have been there. Whoever answers
        // next has to be identified again.
        hasVerifiedIdentity = false
        consecutivePingFailures += 1

        // The helper not answering is the outcome that was asked for, not a fault to repair.
        // Re-registering here is what undid the removal roughly a second after it happened —
        // the dropped connection reports one failure and the ping it prompts reports the
        // second, which is the whole budget the recovery needs.
        if wasRemovedByUser {
            return publishing(.degraded(.notRegistered))
        }

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
            // And it retires the readings banked against the record, which a helper that
            // answers has just outvoted. They are not evidence about the helper the app now
            // has: `register()` returning and the ping succeeding both land before Background
            // Task Management necessarily reports the new record, so leaving the count standing
            // let a stale reading finish a verdict — telling the user there was no helper
            // moments after they installed one and it started working.
            consecutiveAbsentStatuses = 0
            consecutivePendingApprovals = 0
        }
        return [.publish(newHealth)]
    }
}
