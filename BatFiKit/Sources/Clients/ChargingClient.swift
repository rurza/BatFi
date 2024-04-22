//
//  ChargingClient.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Dependencies
import DependenciesMacros
import Shared

@DependencyClient
public struct ChargingClient {
    public var turnOnAutoChargingMode: @Sendable () async throws -> Void
    public var inhibitCharging: @Sendable () async throws -> Void
    public var forceDischarge: @Sendable () async throws -> Void
    public var chargingStatus: @Sendable () async throws -> SMCChargingStatus
    public var enableSystemChargeLimit: @Sendable () async throws -> Void
}

extension ChargingClient: TestDependencyKey {
    public static var testValue: ChargingClient = .init()
}

public extension DependencyValues {
    var chargingClient: ChargingClient {
        get { self[ChargingClient.self] }
        set { self[ChargingClient.self] = newValue }
    }
}
