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
    public var currentPowerSourceState: () throws -> PowerState

    public init(
        powerSourceChanges: @escaping () -> AsyncStream<PowerState>,
        currentPowerSourceState: @escaping () throws -> PowerState
    ) {
        self.powerSourceChanges = powerSourceChanges
        self.currentPowerSourceState = currentPowerSourceState
    }

    public static var testValue: PowerSourceClient = unimplemented()
}

extension DependencyValues {
    public var powerSourceClient: PowerSourceClient {
        get { self[PowerSourceClient.self] }
        set { self[PowerSourceClient.self] = newValue }
    }
}

