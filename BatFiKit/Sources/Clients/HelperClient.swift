//
//  HelperClient.swift
//  BatFi
//
//  Created by Adam on 22/04/2023.
//

import AppShared
import Dependencies
import DependenciesMacros
import ServiceManagement

@DependencyClient
public struct HelperClient: Sendable {
    public var installHelper: @Sendable () async throws -> Void
    public var removeHelper: @Sendable () async throws -> Void
    public var helperStatus: @Sendable () async -> SMAppService.Status = { .notFound }
    public var observeHelperStatus: @Sendable () -> AsyncStream<SMAppService.Status> = { AsyncStream { _ in } }
    public var quitHelper: @Sendable () async throws -> Void
    public var pingHelper: @Sendable () async throws -> Bool
    /// Whose helper is actually running. Total by construction — every failure path answers
    /// `.undetermined` rather than throwing, because the policy on the other side must
    /// always reach a verdict once it has asked for one.
    public var helperOwnership: @Sendable () async -> HelperOwnership = { .undetermined("Not implemented") }
}

extension HelperClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: HelperClient = .init()
}

public extension DependencyValues {
    var helperClient: HelperClient {
        get { self[HelperClient.self] }
        set { self[HelperClient.self] = newValue }
    }
}
