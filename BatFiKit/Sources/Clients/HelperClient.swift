//
//  HelperClient.swift
//  BatFi
//
//  Created by Adam on 22/04/2023.
//

import Dependencies
import DependenciesMacros
import ServiceManagement

@DependencyClient
public struct HelperClient {
    public var installHelper: () async throws -> Void
    public var removeHelper: () async throws -> Void
    public var helperStatus: () async -> SMAppService.Status = { .notFound }
    public var observeHelperStatus: () -> AsyncStream<SMAppService.Status> = { AsyncStream { _ in } }
    public var quitHelper: () async throws -> Void
    public var pingHelper: () async throws -> Void
}

extension HelperClient: TestDependencyKey {
    public static var testValue: HelperClient = .init()
}

public extension DependencyValues {
    var helperClient: HelperClient {
        get { self[HelperClient.self] }
        set { self[HelperClient.self] = newValue }
    }
}
