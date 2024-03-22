//
//  Persistence.swift
//
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import Dependencies
import Foundation

public struct Persistence: TestDependencyKey {
    public var savePowerState: (_ powerState: PowerState, _ mode: AppChargingMode) async throws -> Void
    public var fetchPowerStatePoint: (_ fromDate: Date, _ toDate: Date) async throws -> [PowerStatePoint]
    public var powerStateDidChange: () async -> AsyncStream<Void>

    public init(
        savePowerState: @escaping (PowerState, AppChargingMode) async throws -> Void,
        fetchPowerStatePoint: @escaping (Date, Date) async throws -> [PowerStatePoint],
        observePowerStatePoints: @escaping () async -> AsyncStream<Void>
    ) {
        self.savePowerState = savePowerState
        self.fetchPowerStatePoint = fetchPowerStatePoint
        powerStateDidChange = observePowerStatePoints
    }

    public static var testValue: Persistence = unimplemented()
}

public extension DependencyValues {
    var persistence: Persistence {
        get { self[Persistence.self] }
        set { self[Persistence.self] = newValue }
    }
}
