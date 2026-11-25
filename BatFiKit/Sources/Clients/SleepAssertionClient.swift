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
public struct SleepAssertionClient: Sendable {
    public var preventAutomaticSleepIfNeeded: @Sendable (_ preventSleep: Bool) async -> Void
    public var preventsAutomaticSleep: @Sendable () async -> Bool = { false }
    // newer method, uses pmset
    public var disableSleep: @Sendable (_: Bool) async throws -> Void
    /// The live system-wide `SleepDisabled` value, or `nil` where it could not be read.
    ///
    /// System-wide and settable by hand, so BatFi asks before disabling sleep itself —
    /// a flag that was already up is somebody else's to take down.
    public var systemSleepIsDisabled: @Sendable () async -> Bool? = { nil }
}

extension SleepAssertionClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: SleepAssertionClient = .init()
}

public extension DependencyValues {
    var sleepAssertionClient: SleepAssertionClient {
        get { self[SleepAssertionClient.self] }
        set { self[SleepAssertionClient.self] = newValue }
    }
}
