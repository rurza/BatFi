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
    }

    public enum Action: Sendable, Equatable {
        case verifyWithPing
        case installHelper
        /// Unregister then re-register. Mutates BTM state; emitted at most once per launch.
        case retryRegistrationOnce
        case publish(HelperHealth)
        case showGuidance
        case scheduleProbe(Duration)
    }

    public static let firstProbeDelay = Duration.seconds(5)
    public static let maxProbeDelay = Duration.seconds(60)

    public private(set) var health: HelperHealth = .unknown

    /// Consecutive failures since the last success or re-registration. A lone failure is
    /// treated as transient — XPC calls die for reasons that have nothing to do with the
    /// helper being wedged — so nothing mutating happens until a second one confirms it.
    private var consecutivePingFailures = 0
    /// Once per launch, deliberately. Repeated re-registration is the behaviour most
    /// plausibly associated with wedging the record this whole type exists to detect.
    private var hasRetriedRegistration = false
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
            return publishing(.healthy)
        case .pingFailed:
            return handlePingFailure()
        case let .retryFinished(error):
            guard let error else {
                // The re-registration itself worked; whether it helped is a question only a
                // ping can answer. Seed the count so that one more failure is conclusive —
                // we already have two failures on record from before the retry.
                consecutivePingFailures = 1
                return [.verifyWithPing]
            }
            return concluding(.degraded(.installFailed(error)))
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
            return publishing(.degraded(.notRegistered)) + [.installHelper]
        case .requiresApproval:
            // Only the user can clear this, so re-registering would just churn the record.
            return concluding(.degraded(.requiresApproval), scheduleProbe: false)
        case .notFound:
            return concluding(.degraded(.notRegistered), scheduleProbe: false)
        }
    }

    private mutating func handlePingFailure() -> [Action] {
        consecutivePingFailures += 1
        guard consecutivePingFailures >= 2 else { return [.verifyWithPing] }

        if !hasRetriedRegistration {
            hasRetriedRegistration = true
            consecutivePingFailures = 0
            return [.retryRegistrationOnce]
        }
        return concluding(.degraded(.registeredButUnreachable))
    }

    /// Publishes a settled failure. Guidance is emitted only on entering the state, so the
    /// repeating probe does not re-nag, and probing continues so that a repair the app
    /// cannot make itself — the user toggling Login Items — is noticed without a relaunch.
    private mutating func concluding(_ newHealth: HelperHealth, scheduleProbe: Bool = true) -> [Action] {
        let isNewBreakage = health != newHealth
        var actions = publishing(newHealth)
        if isNewBreakage {
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
        return [.publish(newHealth)]
    }
}
