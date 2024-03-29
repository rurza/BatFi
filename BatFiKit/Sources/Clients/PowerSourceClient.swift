//
//  PowerSourceClient.swift
//
//
//  Created by Adam on 28/04/2023.
//

import AppShared
import Dependencies
import Foundation

public enum PowerSourceError: Error {
    case infoMissing
}

public struct PowerSourceClient: TestDependencyKey {
    public var powerSourceChanges: () -> AsyncStream<PowerState>
    public var currentPowerSourceState: () async throws -> PowerState

    public init(
        powerSourceChanges: @escaping () -> AsyncStream<PowerState>,
        currentPowerSourceState: @escaping () async throws -> PowerState
    ) {
        self.powerSourceChanges = powerSourceChanges
        self.currentPowerSourceState = currentPowerSourceState
    }

    public static var testValue: PowerSourceClient = unimplemented()
}

public extension DependencyValues {
    var powerSourceClient: PowerSourceClient {
        get { self[PowerSourceClient.self] }
        set { self[PowerSourceClient.self] = newValue }
    }
}
