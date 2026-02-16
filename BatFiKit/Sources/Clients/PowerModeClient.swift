//
//  PowerModeClient.swift
//  BatFiKit
//
//  Created by Adam Różyński on 20.11.2024.
//

import Dependencies

public enum PowerMode: Sendable {
    case low, normal, high
}

public enum PowerModeClientError: Error {
    case unsupportedMode
}

public struct PowerModeClient: TestDependencyKey, Sendable {
    public var getCurrentPowerMode: @Sendable () async throws -> (PowerMode, Bool)
    public var setPowerMode: @Sendable (PowerMode, _ lowPowerModeOnly: Bool) async throws -> Void
    public var observePowerMode: @Sendable () -> AsyncStream<PowerMode>

    public init(
        getCurrentPowerMode: @escaping @Sendable () async throws -> (PowerMode, Bool),
        setPowerMode: @escaping @Sendable (PowerMode, Bool) async throws -> Void,
        observePowerMode: @escaping @Sendable () -> AsyncStream<PowerMode>
    ) {
        self.getCurrentPowerMode = getCurrentPowerMode
        self.setPowerMode = setPowerMode
        self.observePowerMode = observePowerMode
    }

    nonisolated(unsafe) public static var testValue: PowerModeClient = unimplemented()
}

extension DependencyValues {
    public var powerModeClient: PowerModeClient {
        get { self[PowerModeClient.self] }
        set { self[PowerModeClient.self] = newValue }
    }
}
