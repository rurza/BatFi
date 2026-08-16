//
//  HelperHealthPolicyTests.swift
//  BatFi
//
//  The rules that keep helper recovery from becoming the thing that breaks the helper.
//  The mutating recovery (unregister/register) is the action suspected of wedging the BTM
//  record in the first place, so "at most once" is the property under test here, alongside
//  the guard that stops a single transient XPC failure from triggering it at all.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct HelperHealthPolicyTests {
    /// Drives the policy to the point where it has just been told the service is enabled
    /// and has asked for its first verifying ping.
    private func enabledAndVerifying() -> HelperHealthPolicy {
        var policy = HelperHealthPolicy()
        _ = policy.handle(.statusObserved(.enabled))
        return policy
    }

    /// Drives the policy all the way to healthy: reachable *and* identified as ours.
    @discardableResult
    private func reachAndIdentify(_ policy: inout HelperHealthPolicy) -> [HelperHealthPolicy.Action] {
        _ = policy.handle(.pingSucceeded)
        return policy.handle(.identityChecked(.ours))
    }

    /// A ping proves reachability and nothing else. The helper belonging to another copy of
    /// BatFi answers one exactly as well as our own, so reporting healthy on a ping alone is
    /// how the wrong helper used to pass for the right one.
    @Test("A successful ping asks who answered before believing it")
    func pingSucceededVerifiesIdentityFirst() {
        var policy = enabledAndVerifying()

        let actions = policy.handle(.pingSucceeded)

        #expect(actions == [.verifyIdentity])
        #expect(policy.health != .healthy)
    }

    @Test("Reachable plus identified as ours is what reports healthy")
    func identifiedOwnHelperPublishesHealthy() {
        var policy = enabledAndVerifying()

        let actions = reachAndIdentify(&policy)

        #expect(actions.contains(.publish(.healthy)))
        #expect(policy.health == .healthy)
    }

    /// Once established, identity is not re-asked on every ping — only on the events that
    /// could have changed which process is answering.
    @Test("Identity is established once, not re-checked on every ping")
    func identityIsNotRecheckedWhileUnchanged() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)

        let actions = policy.handle(.pingSucceeded)

        #expect(actions == [.publish(.healthy)])
    }

    // MARK: - Removal the user asked for

    /// The reported bug. Removing the helper makes it stop answering, which is exactly what a
    /// wedged helper looks like — so the recovery re-registered it about a second later and
    /// the removal never took. The two ping failures arrive on their own: the dropped XPC
    /// connection reports one, and the `verifyWithPing` it prompts reports the second.
    @Test("A removal the user asked for is not repaired by re-registering")
    func userRemovalDoesNotTriggerReregistration() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)

        policy.handle(.removalRequestedByUser)
        let first = policy.handle(.pingFailed)
        let second = policy.handle(.pingFailed)

        #expect(!first.contains(.retryRegistrationOnce))
        #expect(!second.contains(.retryRegistrationOnce))
    }

    /// Removing it is not a fault to report. The guidance for an absent helper offers to
    /// install one, which is the opposite of what was just asked for.
    @Test("A removal the user asked for stops belief without announcing a failure")
    func userRemovalPublishesWithoutGuidance() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)

        let actions = policy.handle(.removalRequestedByUser)

        #expect(actions.contains(.publish(.degraded(.notRegistered))))
        #expect(!actions.contains(.showGuidance))
        #expect(policy.health != .healthy)
    }

    /// The absence is now real, so the status stream corroborates it and the policy reaches
    /// its verdict — but the alert that verdict carries offers to install a helper, which is
    /// the thing that was just deliberately removed.
    @Test("A removal the user asked for is not reported back to them as a missing helper")
    func userRemovalIsNotAnnouncedAsAFault() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)
        policy.handle(.removalRequestedByUser)

        var actions: [HelperHealthPolicy.Action] = []
        for _ in 0 ..< HelperHealthPolicy.absentStatusBudget {
            actions += policy.handle(.statusObserved(.notRegistered))
        }

        #expect(!actions.contains(.showGuidance))
    }

    /// The suppression is scoped to the removal, not to the rest of the launch. Once a
    /// registration exists again the helper can wedge like any other, and the one recovery
    /// this policy is allowed has to still be there for it.
    @Test("Recovery is available again once a registration exists")
    func recoveryReturnsAfterReinstall() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)
        policy.handle(.removalRequestedByUser)

        policy.handle(.statusObserved(.enabled))
        policy.handle(.pingFailed)
        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.retryRegistrationOnce))
    }

    @Test("Status .enabled alone never reports healthy — it only asks for a ping")
    func enabledStatusAloneIsNotHealthy() {
        var policy = HelperHealthPolicy()

        let actions = policy.handle(.statusObserved(.enabled))

        #expect(actions == [.verifyWithPing])
        #expect(policy.health != .healthy)
    }

    @Test("A single ping failure re-verifies instead of re-registering")
    func singlePingFailureDoesNotRetryRegistration() {
        var policy = enabledAndVerifying()

        let actions = policy.handle(.pingFailed)

        #expect(actions == [.verifyWithPing])
        #expect(!actions.contains(.retryRegistrationOnce))
    }

    @Test("A second consecutive ping failure triggers the one-shot re-registration")
    func sustainedFailureRetriesRegistration() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)

        let actions = policy.handle(.pingFailed)

        #expect(actions == [.retryRegistrationOnce])
    }

    @Test("Registration is never retried a second time, however long it keeps failing")
    func registrationRetriesAtMostOnce() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)          // triggers the single retry
        _ = policy.handle(.retryFinished(error: nil))

        var retriesAfterFirst = 0
        for _ in 0 ..< 10 {
            let actions = policy.handle(.pingFailed)
            retriesAfterFirst += actions.filter { $0 == .retryRegistrationOnce }.count
            _ = policy.handle(.statusObserved(.enabled))
        }

        #expect(retriesAfterFirst == 0)
    }

    /// The whole post-registration sequence, which is where the interesting distinction
    /// lives: unreachable-so-far versus unreachable-and-unfixable-from-here.
    @discardableResult
    private func driveToStaleRegistration(_ policy: inout HelperHealthPolicy) -> [HelperHealthPolicy.Action] {
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)              // triggers the single re-registration
        _ = policy.handle(.retryFinished(error: nil))
        for _ in 1 ..< HelperHealthPolicy.postRegistrationProbeBudget {
            _ = policy.handle(.pingFailed)          // still only interim
        }
        return policy.handle(.pingFailed)           // the verdict
    }

    /// A register that reports success proves nothing: `SMAppService.unregister()` leaves the
    /// Background Task Management item in place and merely disables it, so the `register()`
    /// after it re-finds the very same record — poisoned launch constraint included — and
    /// returns cleanly. Believing that success is how the app used to tell the user its
    /// helper was fine while macOS refused to spawn it every ten seconds.
    @Test("Unreachable after a successful re-registration is reported as needing a user reset")
    func exhaustedRecoveryReportsStaleRegistration() {
        var policy = enabledAndVerifying()

        let actions = driveToStaleRegistration(&policy)

        #expect(actions.contains(.publish(.degraded(.staleRegistrationNeedsUserReset))))
        #expect(actions.contains(.showGuidance))
        #expect(policy.health == .degraded(.staleRegistrationNeedsUserReset))
    }

    /// The verdict is worth waiting for. launchd throttles a service that just failed to
    /// spawn — "Pushing respawn out by 10 seconds" — so the first probe after a repair can
    /// fail on a record that is about to work perfectly well. Concluding there would send
    /// the user to System Settings to fix nothing.
    @Test("The first failure after a re-registration is interim, not a verdict")
    func firstPostRegistrationFailureIsNotConclusive() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))

        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.verifyWithPing))
        #expect(!actions.contains(.showGuidance))
        #expect(policy.health != .degraded(.staleRegistrationNeedsUserReset))
    }

    /// Interim is not the same as trusted. The charge limit must stop being driven through a
    /// daemon that is not answering, even while the policy is still deciding what to say.
    @Test("An unreachable helper is distrusted immediately, before the verdict")
    func interimFailureStopsTrustingTheHelper() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))

        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.publish(.degraded(.registeredButUnreachable))))
        #expect(policy.health != .healthy)
    }

    /// Turning the item off in System Settings is what destroys the record and its stale
    /// constraint — the one repair that works, and the one the app cannot perform. What it
    /// surfaces as is `.notRegistered`, and the install over it has to be given a clean slate
    /// rather than inheriting the dead record's failures.
    @Test("A user reset clears the way for a fresh install rather than a repeated verdict")
    func userResetAllowsRecovery() {
        var policy = enabledAndVerifying()
        driveToStaleRegistration(&policy)

        // The toggle-off leaves no record, which is reported rather than silently
        // reinstalled — but crucially it also retires the stale verdict, so what follows is
        // judged as a new install and not as more evidence against the old record.
        let reset = policy.handle(.statusObserved(.notRegistered))
        #expect(reset.contains(.publish(.degraded(.notRegistered))))
        #expect(policy.health != .degraded(.staleRegistrationNeedsUserReset))

        // One slow probe against the newly minted record must not re-run the verdict.
        let interim = policy.handle(.pingFailed)
        #expect(!interim.contains(.showGuidance))
        #expect(policy.health != .degraded(.staleRegistrationNeedsUserReset))

        _ = policy.handle(.pingSucceeded)
        #expect(policy.handle(.identityChecked(.ours)).contains(.publish(.healthy)))
        #expect(policy.health == .healthy)
    }

    /// Two copies on disk, both present, the other one holding the registration. The
    /// takeover is the right response and it ran; it simply did not work, because macOS
    /// refused to launch this copy's helper. What must not happen next is the unreachable
    /// path spending a *second* unregister/register on the same launch.
    @Test("A takeover already spends the launch's one re-registration")
    func takeoverCountsAsTheRegistrationAttempt() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)
        _ = policy.handle(.identityChecked(.foreign(conflict)))   // the takeover
        _ = policy.handle(.takeoverFinished(error: nil))

        var retries = 0
        for _ in 0 ..< 10 {
            retries += policy.handle(.pingFailed).filter { $0 == .retryRegistrationOnce }.count
        }

        #expect(retries == 0)
    }

    /// Reporting a known conflict as a stale registration tells the user a deleted copy left
    /// a record behind, and sends them to Login Items to clear it. Both are false while the
    /// other copy is sitting on disk holding the registration, and toggling the item fixes
    /// nothing. Only the conflict knows where that copy is.
    @Test("An unreachable helper after a takeover is reported as the conflict, not as stale")
    func unreachableAfterTakeoverKeepsTheConflict() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)
        _ = policy.handle(.identityChecked(.foreign(conflict)))
        _ = policy.handle(.takeoverFinished(error: nil))

        var actions: [HelperHealthPolicy.Action] = []
        for _ in 0 ..< HelperHealthPolicy.postRegistrationProbeBudget {
            actions = policy.handle(.pingFailed)
        }

        #expect(actions.contains(.publish(.degraded(.foreignHelper(conflict)))))
        #expect(actions.contains(.showGuidance))
        #expect(policy.health == .degraded(.foreignHelper(conflict)))
        #expect(policy.health != .degraded(.staleRegistrationNeedsUserReset))
    }

    /// Re-registering is what the app has already established does not work here. Doing it
    /// again would be futile and not merely wasteful: the churn is what earns BatFi
    /// "Exceeded max notifications" from Background Task Management.
    @Test("The unfixable state never re-registers, however long it persists")
    func staleRegistrationNeverRetriesRegistration() {
        var policy = enabledAndVerifying()
        driveToStaleRegistration(&policy)

        var retries = 0
        for _ in 0 ..< 10 {
            retries += policy.handle(.pingFailed).filter { $0 == .retryRegistrationOnce }.count
        }

        #expect(retries == 0)
    }

    @Test("Guidance is asked for once per breakage, not on every probe")
    func guidanceIsNotRepeatedWhileStillDegraded() {
        var policy = enabledAndVerifying()
        driveToStaleRegistration(&policy)     // enters degraded, emits guidance

        let actions = policy.handle(.pingFailed)

        #expect(!actions.contains(.showGuidance))
    }

    @Test("While degraded, the policy keeps probing so a manual repair is noticed")
    func degradedSchedulesProbe() {
        var policy = enabledAndVerifying()
        let actions = driveToStaleRegistration(&policy)

        #expect(actions.contains(.scheduleProbe(HelperHealthPolicy.firstProbeDelay)))
    }

    @Test("Probe delay doubles and stops at the ceiling")
    func probeBackoffAdvancesToCeiling() {
        var policy = enabledAndVerifying()
        driveToStaleRegistration(&policy)

        var delays: [Duration] = []
        for _ in 0 ..< 5 {
            let actions = policy.handle(.pingFailed)
            for action in actions {
                if case let .scheduleProbe(delay) = action { delays.append(delay) }
            }
        }

        #expect(delays == [.seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60)])
    }

    @Test("Recovery reports healthy and resets the probe backoff")
    func recoveryResetsBackoff() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)          // backoff has advanced past the first delay

        #expect(reachAndIdentify(&policy).contains(.publish(.healthy)))

        _ = policy.handle(.pingFailed)
        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.scheduleProbe(HelperHealthPolicy.firstProbeDelay)))
    }

    @Test("A repeated identical status is ignored, so the backoff owns retesting")
    func repeatedStatusDoesNotReVerify() {
        // The status stream yields every 1.5s including duplicates. Acting on each one
        // would ping continuously while degraded and make the probe backoff meaningless —
        // and a wedged record reports .enabled on every one of those ticks.
        var policy = enabledAndVerifying()
        driveToStaleRegistration(&policy)     // settled into degraded

        let actions = policy.handle(.statusObserved(.enabled))

        #expect(actions.isEmpty)
    }

    @Test("A status that actually changes is acted on")
    func changedStatusIsActedOn() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)

        _ = policy.handle(.statusObserved(.notRegistered))
        let actions = policy.handle(.statusObserved(.enabled))

        #expect(actions == [.verifyWithPing])
    }

    @Test("requiresApproval goes straight to guidance and never re-registers")
    func requiresApprovalDoesNotRetryRegistration() {
        var policy = HelperHealthPolicy()

        let actions = policy.handle(.statusObserved(.requiresApproval))

        #expect(actions.contains(.publish(.degraded(.requiresApproval))))
        #expect(actions.contains(.showGuidance))
        #expect(!actions.contains(.retryRegistrationOnce))
        #expect(!actions.contains(.verifyWithPing))
    }

    /// Registering a privileged daemon makes macOS post a background-item notification and
    /// often demand an approval. Doing that unasked, seconds after launch, is
    /// indistinguishable from the app misbehaving — so the policy reports the absence and
    /// lets the guidance's button be what asks.
    @Test("No helper means asking the user, not installing unasked")
    func notRegisteredAsksRatherThanInstalling() {
        var policy = HelperHealthPolicy()

        let actions = observeSustainedAbsence(&policy)

        #expect(actions.contains(.publish(.degraded(.notRegistered))))
        #expect(actions.contains(.showGuidance))
        #expect(!actions.contains(.installHelper))
        #expect(!actions.contains(.retryRegistrationOnce))
    }

    /// The state a vanished record actually reports. Observed live: `register()` logged
    /// success, the helper never answered, and the next launch read `.notFound` and settled
    /// into a verdict that told the user to re-enable a Login Items entry which did not
    /// exist — there is nothing to toggle, because there is no record.
    ///
    /// It is the same situation as `.notRegistered` and must reach the same place: say so,
    /// and offer the button that installs.
    @Test("notFound is the same absence as notRegistered, not a dead end")
    func notFoundIsReportedAsNotRegistered() {
        var policy = HelperHealthPolicy()

        let actions = observeSustainedAbsence(&policy, .notFound)

        #expect(actions.contains(.publish(.degraded(.notRegistered))))
        #expect(actions.contains(.showGuidance))
        #expect(!actions.contains(.installHelper))
    }

    /// A failing install still has to reach a verdict, and it has to be the one that carries
    /// the real reason — `.installFailed` names what went wrong, where the old `.notFound`
    /// path could only offer Login Items advice that did not apply.
    @Test("An install that fails from notFound is reported with its reason")
    func notFoundInstallFailureIsReported() {
        var policy = HelperHealthPolicy()
        _ = policy.handle(.statusObserved(.notFound))

        let actions = policy.handle(.retryFinished(error: "The plist could not be found"))

        #expect(actions.contains(.publish(.degraded(.installFailed("The plist could not be found")))))
        #expect(actions.contains(.showGuidance))
    }

    /// The complaint this rule comes from: the app launched, and macOS asked for approval
    /// before the user had clicked anything. `.installHelper` is the only action that makes
    /// macOS prompt, so nothing the policy decides on its own may emit it — it exists for
    /// the button, and for the button only.
    @Test("Nothing the policy decides by itself ever asks macOS to install")
    func installIsNeverEmittedWithoutTheUser() {
        var policy = HelperHealthPolicy()
        var emitted: [HelperHealthPolicy.Action] = []

        for status in [HelperServiceStatus.notFound, .notRegistered, .requiresApproval, .enabled] {
            emitted += policy.handle(.statusObserved(status))
        }
        emitted += policy.handle(.pingFailed)
        emitted += policy.handle(.pingFailed)
        emitted += policy.handle(.retryFinished(error: nil))
        emitted += policy.handle(.pingFailed)
        emitted += policy.handle(.pingFailed)

        #expect(!emitted.contains(.installHelper))
    }

    // MARK: - A missing record, corroborated

    /// The complaint this rule comes from: a modal seconds after launch offering to install a
    /// helper that was installed, running, and answering.
    ///
    /// `SMAppService.status` reads Background Task Management, not the daemon, and the answer
    /// is not reliable the instant the app asks — which at launch is the first thing it does,
    /// from `observeHelperStatus()`'s immediate first yield. Observed live: the app published
    /// this absence while its own helper was running, and a ping to it succeeded ten seconds
    /// later.
    ///
    /// Every other verdict in this policy waits for a second opinion — two ping failures
    /// before anything mutating, two more before the unfixable verdict. This one concluded on
    /// a single reading, and it is the one reading taken before the machine has settled.
    @Test("A single absent reading distrusts the helper but tells the user nothing")
    func oneAbsentStatusIsNotAVerdict() {
        var policy = HelperHealthPolicy()

        let actions = policy.handle(.statusObserved(.notRegistered))

        #expect(actions == [.publish(.degraded(.notRegistered))])
        #expect(!actions.contains(.showGuidance))
    }

    /// The launch this is all for: BTM had not answered properly yet, and by the next poll the
    /// record it had failed to report was there all along. Nothing should have been said, and
    /// the helper should end up believed like any other.
    @Test("A record that appears within the window is never reported missing")
    func absenceContradictedByTheNextReadingIsNeverAnnounced() {
        var policy = HelperHealthPolicy()
        var emitted: [HelperHealthPolicy.Action] = []

        for _ in 1 ..< HelperHealthPolicy.absentStatusBudget {
            emitted += policy.handle(.statusObserved(.notFound))
        }
        emitted += policy.handle(.statusObserved(.enabled))
        emitted += reachAndIdentify(&policy)

        #expect(!emitted.contains(.showGuidance))
        #expect(policy.health == .healthy)
    }

    /// Corroboration delays the verdict; it does not cancel it. A record that is genuinely
    /// gone — the copy of BatFi that registered it having been deleted — still has to reach
    /// the alert whose button installs a new one.
    @Test("An absence that survives the window is reported")
    func sustainedAbsenceIsAnnounced() {
        var policy = HelperHealthPolicy()

        let actions = observeSustainedAbsence(&policy)

        #expect(actions.contains(.showGuidance))
        #expect(policy.health == .degraded(.notRegistered))
    }

    /// The stream keeps yielding the same absence every 1.5s for as long as it lasts, and none
    /// of those readings is new information.
    @Test("The absence is announced once, not on every poll that follows")
    func absenceIsAnnouncedOnce() {
        var policy = HelperHealthPolicy()
        observeSustainedAbsence(&policy)

        var later: [HelperHealthPolicy.Action] = []
        for _ in 0 ..< 10 {
            later += policy.handle(.statusObserved(.notRegistered))
        }

        #expect(later.isEmpty)
    }

    /// Absence has to be consecutive to count. An `.enabled` in between says the record is
    /// there, which retires whatever was banked against its absence.
    @Test("A reading that finds the record resets the corroboration")
    func enabledResetsTheAbsenceCount() {
        var policy = HelperHealthPolicy()
        for _ in 1 ..< HelperHealthPolicy.absentStatusBudget {
            _ = policy.handle(.statusObserved(.notRegistered))
        }
        _ = policy.handle(.statusObserved(.enabled))

        let actions = policy.handle(.statusObserved(.notRegistered))

        #expect(!actions.contains(.showGuidance))
    }

    /// A helper answering is better evidence than any number of readings about whether a record
    /// exists, and it arrives first: the install button's `register()` returns, the ping
    /// succeeds, and Background Task Management catches up in its own time. A reading banked
    /// before that must not be allowed to complete a verdict against a helper that is now
    /// doing the work — which would report "there is no helper" moments after installing one.
    @Test("A helper that starts answering retires the absence banked against it")
    func healthRetiresTheAbsenceCount() {
        var policy = HelperHealthPolicy()
        _ = policy.handle(.statusObserved(.notFound))    // one absent reading banked
        _ = policy.handle(.pingSucceeded)
        reachAndIdentify(&policy)                        // ... and then the helper answers

        var later: [HelperHealthPolicy.Action] = []
        for _ in 1 ..< HelperHealthPolicy.absentStatusBudget {
            later += policy.handle(.statusObserved(.notFound))
        }

        #expect(!later.contains(.showGuidance))
    }

    /// Feeds the absent status as many times as the stream would before the policy is allowed
    /// to conclude anything from it, and returns the actions from the reading that concludes.
    @discardableResult
    private func observeSustainedAbsence(
        _ policy: inout HelperHealthPolicy,
        _ status: HelperServiceStatus = .notRegistered
    ) -> [HelperHealthPolicy.Action] {
        var actions: [HelperHealthPolicy.Action] = []
        for _ in 0 ..< HelperHealthPolicy.absentStatusBudget {
            actions = policy.handle(.statusObserved(status))
        }
        return actions
    }

    // MARK: - Ownership

    private var conflict: HelperOwnershipConflict {
        HelperOwnershipConflict(
            kind: .otherBundle,
            runningExecutablePath: "/Users/adam/Downloads/BatFi.app/Contents/MacOS/BatFiHelper",
            expectedExecutablePath: "/Applications/BatFi.app/Contents/MacOS/BatFiHelper",
            runningVersion: "99999",
            owningAppPath: "/Users/adam/Downloads/BatFi.app"
        )
    }

    @Test("A helper belonging to another copy is never reported healthy")
    func foreignHelperIsNotHealthy() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)

        let actions = policy.handle(.identityChecked(.foreign(conflict)))

        #expect(actions.contains(.publish(.degraded(.foreignHelper(conflict)))))
        #expect(actions.contains(.takeOwnership(conflict)))
        #expect(policy.health != .healthy)
    }

    /// Two copies of BatFi open at once each see the other's helper as foreign. Unbounded,
    /// they would trade the registration back and forth for as long as both stay running.
    @Test("Ownership is taken at most once per launch, however long the conflict lasts")
    func takeoverHappensAtMostOnce() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)
        _ = policy.handle(.identityChecked(.foreign(conflict)))   // the one takeover
        _ = policy.handle(.takeoverFinished(error: nil))

        var takeovers = 0
        for _ in 0 ..< 10 {
            _ = policy.handle(.pingSucceeded)
            let actions = policy.handle(.identityChecked(.foreign(conflict)))
            takeovers += actions.filter { $0 == .takeOwnership(conflict) }.count
        }

        #expect(takeovers == 0)
    }

    @Test("A conflict that survives the takeover asks for guidance and keeps probing")
    func unresolvedConflictConcludes() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)
        _ = policy.handle(.identityChecked(.foreign(conflict)))
        _ = policy.handle(.takeoverFinished(error: nil))
        _ = policy.handle(.pingSucceeded)

        let actions = policy.handle(.identityChecked(.foreign(conflict)))

        #expect(actions.contains(.publish(.degraded(.foreignHelper(conflict)))))
        #expect(actions.contains(.showGuidance))
        #expect(actions.contains(.scheduleProbe(HelperHealthPolicy.firstProbeDelay)))
    }

    /// A takeover reported as successful proves nothing on its own — `register()` returns
    /// cleanly from a copy that did not get the record, which is the defect being worked
    /// around. Only a fresh identity check settles it.
    @Test("A finished takeover re-verifies rather than assuming it worked")
    func takeoverSuccessReVerifies() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)
        _ = policy.handle(.identityChecked(.foreign(conflict)))

        let actions = policy.handle(.takeoverFinished(error: nil))

        #expect(actions == [.verifyWithPing])
        #expect(policy.handle(.pingSucceeded) == [.verifyIdentity])
    }

    /// The takeover can fail for a reason that is not an installation problem at all — the
    /// other copy being open. Reporting it as a failed install would send the user to Login
    /// Items to repair a registration that is working as designed.
    @Test("A failed takeover is still reported as a conflict, not as a failed install")
    func failedTakeoverKeepsTheConflict() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)
        _ = policy.handle(.identityChecked(.foreign(conflict)))

        let actions = policy.handle(.takeoverFinished(error: "Another copy of BatFi is running from /Users/adam/Downloads/BatFi.app"))

        #expect(actions.contains(.publish(.degraded(.foreignHelper(conflict)))))
        #expect(actions.contains(.showGuidance))
    }

    /// The identity read can fail on its own terms — an unreadable signature, a process that
    /// vanished. That is not evidence of a foreign helper, and treating it as one would cost
    /// every affected user a System Settings approval to fix nothing.
    @Test("An undetermined identity does not trigger a takeover")
    func undeterminedIdentityDoesNotTakeOwnership() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingSucceeded)

        let actions = policy.handle(.identityChecked(.undetermined("could not read the signature")))

        #expect(!actions.contains(.takeOwnership(conflict)))
        #expect(actions.contains(.publish(.healthy)))
    }

    /// A re-registration is precisely an attempt to change which binary launchd starts, so
    /// anything known about the previous process has to be discarded.
    @Test("Re-registration invalidates the established identity")
    func reregistrationForcesReIdentification() {
        var policy = enabledAndVerifying()
        reachAndIdentify(&policy)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)

        _ = policy.handle(.retryFinished(error: nil))

        #expect(policy.handle(.pingSucceeded) == [.verifyIdentity])
    }

    @Test("A failed re-registration is reported with its reason")
    func failedRetryPublishesInstallFailed() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)

        let actions = policy.handle(.retryFinished(error: "Operation not permitted"))

        #expect(actions.contains(.publish(.degraded(.installFailed("Operation not permitted")))))
        #expect(actions.contains(.showGuidance))
    }
}
