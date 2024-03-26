//
//  SleepClient.swift
//
//
//  Created by Adam on 08/05/2023.
//

import Cocoa
import Dependencies

public enum SleepNotification {
    case willSleep
    case didWake
}

public struct SleepClient: TestDependencyKey {
    public var macWillSleep: @Sendable () async -> AsyncStream<Void>
    public var macDidWake: @Sendable () async -> AsyncStream<Void>
    public var screenDidSleep: @Sendable () async -> AsyncStream<Void>
    public var screenDidWake: @Sendable () async -> AsyncStream<Void>
    public var observeMacSleepStatus: @Sendable () async -> AsyncStream<SleepNotification>

    public init(
        macWillSleep: @Sendable @escaping () async -> AsyncStream<Void>,
        macDidWake: @Sendable @escaping () async -> AsyncStream<Void>,
        screenDidSleep: @Sendable @escaping () async -> AsyncStream<Void>,
        screenDidWake: @Sendable @escaping () async -> AsyncStream<Void>,
        observeMacSleepStatus: @Sendable @escaping () async -> AsyncStream<SleepNotification>
    ) {
        self.macWillSleep = macWillSleep
        self.macDidWake = macDidWake
        self.screenDidSleep = screenDidSleep
        self.screenDidWake = screenDidWake
        self.observeMacSleepStatus = observeMacSleepStatus
    }

    public static var testValue: SleepClient = unimplemented()
}

public extension DependencyValues {
    var sleepClient: SleepClient {
        get { self[SleepClient.self] }
        set { self[SleepClient.self] = newValue }
    }
}
