//
//  PowerSourceClient.swift
//
//
//  Created by Adam on 28/04/2023.
//

import AppShared
import Dependencies
import Foundation

public struct PowerSourceClient: TestDependencyKey, Sendable {
    public var powerSourceChanges: @Sendable () -> AsyncStream<PowerState>
    public var currentPowerSourceState: @Sendable () async throws -> PowerState
    public var isRunningOnLaptop: @Sendable () -> Bool

    nonisolated(unsafe) public static var testValue: PowerSourceClient = unimplemented()

    public init(
        powerSourceChanges: @escaping @Sendable () -> AsyncStream<PowerState>,
        currentPowerSourceState: @escaping @Sendable () async throws -> PowerState,
        isRunningOnLaptop: @escaping @Sendable () -> Bool
    ) {
        self.powerSourceChanges = powerSourceChanges
        self.currentPowerSourceState = currentPowerSourceState
        self.isRunningOnLaptop = isRunningOnLaptop
    }
}

public extension DependencyValues {
    var powerSourceClient: PowerSourceClient {
        get { self[PowerSourceClient.self] }
        set { self[PowerSourceClient.self] = newValue }
    }
}
