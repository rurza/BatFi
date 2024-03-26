//
//  SleepAssertionClient.swift
//
//
//  Created by Adam on 23/05/2023.
//

import Dependencies
import Foundation

public struct SleepAssertionClient: TestDependencyKey {
    public var preventSleepIfNeeded: @Sendable (_ preventSleep: Bool) async -> Void

    public init(preventSleepIfNeeded: @escaping @Sendable (Bool) async -> Void) {
        self.preventSleepIfNeeded = preventSleepIfNeeded
    }

    public static var testValue: SleepAssertionClient = unimplemented()
}

public extension DependencyValues {
    var sleepAssertionClient: SleepAssertionClient {
        get { self[SleepAssertionClient.self] }
        set { self[SleepAssertionClient.self] = newValue }
    }
}
