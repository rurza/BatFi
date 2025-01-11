//
//  File.swift
//  BatFiKit
//
//  Created by Adam Różyński on 11.01.2025.
//

import Dependencies
import DependenciesMacros

@DependencyClient
public struct KeychainClient {
    public var saveLicense: (String?) async throws -> Void
    public var getLicense: () async throws -> String?
}

extension KeychainClient: TestDependencyKey {
    public static var testValue: KeychainClient = unimplemented()
}

extension DependencyValues {
    public var keychainClient: KeychainClient {
        get { self[KeychainClient.self] }
        set { self[KeychainClient.self] = newValue }
    }
}
