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

        let install = policy.handle(.statusObserved(.notRegistered))
        #expect(install.contains(.installHelper))

        // One slow probe against the newly minted record must not re-run the verdict.
        let interim = policy.handle(.pingFailed)
        #expect(!interim.contains(.showGuidance))
        #expect(policy.health != .degraded(.staleRegistrationNeedsUserReset))

        _ = policy.handle(.pingSucceeded)
        #expect(policy.handle(.identityChecked(.ours)).contains(.publish(.healthy)))
        #expect(policy.health == .healthy)
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

    @Test("notRegistered installs rather than re-registering")
    func notRegisteredInstalls() {
        var policy = HelperHealthPolicy()

        let actions = policy.handle(.statusObserved(.notRegistered))

        #expect(actions.contains(.installHelper))
        #expect(!actions.contains(.retryRegistrationOnce))
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
