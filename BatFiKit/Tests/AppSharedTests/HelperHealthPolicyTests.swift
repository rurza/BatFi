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

    @Test("A successful ping is the only thing that reports healthy")
    func pingSucceededPublishesHealthy() {
        var policy = enabledAndVerifying()

        let actions = policy.handle(.pingSucceeded)

        #expect(actions.contains(.publish(.healthy)))
        #expect(policy.health == .healthy)
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

    @Test("Conclusive failure reports registeredButUnreachable and asks for guidance")
    func conclusiveFailurePublishesUnreachableAndGuidance() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))

        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.publish(.degraded(.registeredButUnreachable))))
        #expect(actions.contains(.showGuidance))
        #expect(policy.health == .degraded(.registeredButUnreachable))
    }

    @Test("Guidance is asked for once per breakage, not on every probe")
    func guidanceIsNotRepeatedWhileStillDegraded() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))
        _ = policy.handle(.pingFailed)          // enters degraded, emits guidance

        let actions = policy.handle(.pingFailed)

        #expect(!actions.contains(.showGuidance))
    }

    @Test("While degraded, the policy keeps probing so a manual repair is noticed")
    func degradedSchedulesProbe() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))

        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.scheduleProbe(HelperHealthPolicy.firstProbeDelay)))
    }

    @Test("Probe delay doubles and stops at the ceiling")
    func probeBackoffAdvancesToCeiling() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))

        var delays: [Duration] = []
        for _ in 0 ..< 6 {
            let actions = policy.handle(.pingFailed)
            for action in actions {
                if case let .scheduleProbe(delay) = action { delays.append(delay) }
            }
        }

        #expect(delays == [.seconds(5), .seconds(10), .seconds(20), .seconds(40), .seconds(60), .seconds(60)])
    }

    @Test("Recovery reports healthy and resets the probe backoff")
    func recoveryResetsBackoff() {
        var policy = enabledAndVerifying()
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.retryFinished(error: nil))
        _ = policy.handle(.pingFailed)
        _ = policy.handle(.pingFailed)          // backoff has advanced past the first delay

        #expect(policy.handle(.pingSucceeded).contains(.publish(.healthy)))

        _ = policy.handle(.pingFailed)
        let actions = policy.handle(.pingFailed)

        #expect(actions.contains(.scheduleProbe(HelperHealthPolicy.firstProbeDelay)))
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
