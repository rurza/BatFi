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
    public var macWillSleep: () -> AsyncStream<Void>
    public var macDidWake: () -> AsyncStream<Void>
    public var screenDidSleep: () -> AsyncStream<Void>
    public var screenDidWake: () -> AsyncStream<Void>
    public var observeMacSleepStatus: () -> AsyncStream<SleepNotification>

    public init(
        macWillSleep: @escaping () -> AsyncStream<Void>,
        macDidWake: @escaping () -> AsyncStream<Void>,
        screenDidSleep: @escaping () -> AsyncStream<Void>,
        screenDidWake: @escaping () -> AsyncStream<Void>,
        observeMacSleepStatus: @escaping () -> AsyncStream<SleepNotification>
    ) {
        self.macWillSleep = macWillSleep
        self.macDidWake = macDidWake
        self.screenDidSleep = screenDidSleep
        self.screenDidWake = screenDidWake
        self.observeMacSleepStatus = observeMacSleepStatus
    }

    public static var testValue: SleepClient = unimplemented()
}

extension DependencyValues {
    public var sleepClient: SleepClient {
        get { self[SleepClient.self] }
        set { self[SleepClient.self] = newValue }
    }
}
