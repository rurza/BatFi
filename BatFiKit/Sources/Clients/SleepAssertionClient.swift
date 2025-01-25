//
//  SleepAssertionClient.swift
//
//
//  Created by Adam on 23/05/2023.
//

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct SleepAssertionClient {
    public var preventSleepIfNeeded: @Sendable (_ preventSleep: Bool) async -> Void
    public var preventsSleep: @Sendable () async -> Bool = { false }
    // newer method, uses pmset
    public var disableSleep: @Sendable (_: Bool) async throws -> Void
}

extension SleepAssertionClient: TestDependencyKey {
    public static var testValue: SleepAssertionClient = .init()
}

public extension DependencyValues {
    var sleepAssertionClient: SleepAssertionClient {
        get { self[SleepAssertionClient.self] }
        set { self[SleepAssertionClient.self] = newValue }
    }
}
