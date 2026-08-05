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
