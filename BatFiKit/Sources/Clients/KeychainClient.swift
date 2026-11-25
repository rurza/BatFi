//
//  File.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import Dependencies
import DependenciesMacros

@DependencyClient
public struct KeychainClient: Sendable {
    public var saveLicense: @Sendable (String?) async throws -> Void
    public var getLicense: @Sendable () async throws -> String?
    /// Stores the free trial's signed statement, or removes it for nil. A separate item from
    /// the licence: neither operation touches the other's.
    public var saveTrial: @Sendable (String?) async throws -> Void
    /// The stored trial statement, nil when none is stored; throws when the keychain could not
    /// say, which means "not known", never "absent".
    public var getTrial: @Sendable () async throws -> String?
}

extension KeychainClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: KeychainClient = unimplemented()
}

extension DependencyValues {
    public var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
