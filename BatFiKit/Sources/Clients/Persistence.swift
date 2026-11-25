//
//  Persistence.swift
//
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import Dependencies
import Foundation

public struct Persistence: TestDependencyKey, Sendable {
    public var savePowerState: @Sendable (_ powerState: PowerState, _ mode: AppChargingMode) async throws -> Void
    public var fetchPowerStatePoint: @Sendable (_ fromDate: Date, _ toDate: Date) async throws -> [PowerStatePoint]
    public var powerStateDidChange: @Sendable () async -> AsyncStream<Void>
    public var fetchLastDischargeDate: @Sendable () async throws -> Date?
    public var fetchLastFullChargeDate: @Sendable () async throws -> Date?
    public var fullChargeAndDischargeWasInLast30Days: @Sendable () async throws -> (charge: Bool, discharge: Bool)?

    public init(
        savePowerState: @escaping @Sendable (PowerState, AppChargingMode) async throws -> Void,
        fetchPowerStatePoint: @escaping @Sendable (Date, Date) async throws -> [PowerStatePoint],
        observePowerStatePoints: @escaping @Sendable () async -> AsyncStream<Void>,
        fetchLastDischargeDate: @escaping @Sendable () async throws -> Date?,
        fetchLastFullChargeDate: @escaping @Sendable () async throws -> Date?,
        fullChargeAndDischargeWasInLast30Days: @escaping @Sendable () async throws -> (charge: Bool, discharge: Bool)?
    ) {
        self.savePowerState = savePowerState
        self.fetchPowerStatePoint = fetchPowerStatePoint
        powerStateDidChange = observePowerStatePoints
        self.fetchLastDischargeDate = fetchLastDischargeDate
        self.fetchLastFullChargeDate = fetchLastFullChargeDate
        self.fullChargeAndDischargeWasInLast30Days = fullChargeAndDischargeWasInLast30Days
    }

    nonisolated(unsafe) public static var testValue: Persistence = unimplemented()
}

public extension DependencyValues {
    var persistence: Persistence {
        get { self[Persistence.self] }
        set { self[Persistence.self] = newValue }
    }
}
