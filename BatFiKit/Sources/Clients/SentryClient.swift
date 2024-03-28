//
//  SentryClient.swift
//
//
//  Created by Adam Różyński on 28/03/2024.
//

import Dependencies
import DependenciesMacros

@DependencyClient
public struct SentryClient {
    public var startSDK: @Sendable () -> Void = { }
    public var captureMessage: @Sendable (String) -> Void = { _ in }
    public var captureError: @Sendable (Error) -> Void = { _ in }
}

extension SentryClient: TestDependencyKey {
    public static var testValue: SentryClient = .init()
}

extension DependencyValues {
    public var sentryClient: SentryClient {
        get { self[SentryClient.self] }
        set { self[SentryClient.self] = newValue }
    }
}
