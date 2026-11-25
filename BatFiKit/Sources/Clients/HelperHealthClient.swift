//
//  HelperHealthClient.swift
//  BatFi
//
//  Publishes the one authoritative answer to "is the helper actually working?", so that
//  consumers stop each forming their own opinion from `SMAppService.Status`.
//

import AppShared
import Dependencies
import DependenciesMacros
import ServiceManagement

@DependencyClient
public struct HelperHealthClient: Sendable {
    public var currentHealth: @Sendable () async -> HelperHealth = { .unknown }
    public var observeHealth: @Sendable () -> AsyncStream<HelperHealth> = { AsyncStream { _ in } }
    public var setHealth: @Sendable (HelperHealth) async -> Void
    /// Reported by `XPCClient` when a connection dies. A fact, not a verdict — the policy
    /// decides what it means, and confirms with a ping before acting.
    public var reportConnectionFailure: @Sendable () async -> Void
    public var observeConnectionFailures: @Sendable () -> AsyncStream<Void> = { AsyncStream { _ in } }
    /// True while the app is deliberately taking the daemon down — to reclaim it from
    /// another copy, or to repair a record macOS will not start.
    ///
    /// Distinct from any `HelperHealth` value, and deliberately so. Health says what is
    /// true of the helper; this says the app is *in the middle of changing* it, and knows
    /// exactly when the outage starts and ends. Only the second one justifies standing
    /// down, which is why it is not folded into `.degraded`: a helper that is degraded but
    /// answering still limits the battery, and refusing to use it would leave the Mac
    /// charging to 100% with nothing managing it.
    public var isReclaimingHelper: @Sendable () async -> Bool = { false }
    public var setReclaimingHelper: @Sendable (Bool) async -> Void
}

extension HelperHealthClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: HelperHealthClient = .init()
}

public extension DependencyValues {
    var helperHealthClient: HelperHealthClient {
        get { self[HelperHealthClient.self] }
        set { self[HelperHealthClient.self] = newValue }
    }
}

public extension SMAppService.Status {
    var helperServiceStatus: HelperServiceStatus {
        switch self {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        default: .notFound
        }
    }
}
