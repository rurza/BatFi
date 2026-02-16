//
//  SleepClient.swift
//
//
//  Created by Adam on 08/05/2023.
//

import Cocoa
import Dependencies

public enum SleepNotification: Sendable {
    case willSleep
    case didWake
}

public struct SleepClient: TestDependencyKey, Sendable {
    public var macWillSleep: @Sendable () -> AsyncStream<Void>
    public var macDidWake: @Sendable () -> AsyncStream<Void>
    public var screenDidSleep: @Sendable () -> AsyncStream<Void>
    public var screenDidWake: @Sendable () -> AsyncStream<Void>
    public var observeMacSleepStatus: @Sendable () -> AsyncStream<SleepNotification>

    public init(
        macWillSleep: @escaping @Sendable () -> AsyncStream<Void>,
        macDidWake: @escaping @Sendable () -> AsyncStream<Void>,
        screenDidSleep: @escaping @Sendable () -> AsyncStream<Void>,
        screenDidWake: @escaping @Sendable () -> AsyncStream<Void>,
        observeMacSleepStatus: @escaping @Sendable () -> AsyncStream<SleepNotification>
    ) {
        self.macWillSleep = macWillSleep
        self.macDidWake = macDidWake
        self.screenDidSleep = screenDidSleep
        self.screenDidWake = screenDidWake
        self.observeMacSleepStatus = observeMacSleepStatus
    }

    nonisolated(unsafe) public static var testValue: SleepClient = unimplemented()
}

public extension DependencyValues {
    var sleepClient: SleepClient {
        get { self[SleepClient.self] }
        set { self[SleepClient.self] = newValue }
    }
}
