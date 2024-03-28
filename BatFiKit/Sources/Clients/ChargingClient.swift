//
//  ChargingClient.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Dependencies
import Shared

public struct ChargingClient: TestDependencyKey {
    public var turnOnAutoChargingMode: () async throws -> Void
    public var inhibitCharging: () async throws -> Void
    public var forceDischarge: () async throws -> Void
    public var chargingStatus: () async throws -> SMCChargingStatus
    public var enableSystemChargeLimit: () async throws -> Void

    public init(
        turnOnAutoChargingMode: @escaping () async throws -> Void,
        inhibitCharging: @escaping () async throws -> Void,
        forceDischarge: @escaping () async throws -> Void,
        chargingStatus: @escaping () async throws -> SMCChargingStatus,
        enableSystemChargeLimit: @escaping () async throws -> Void
    ) {
        self.turnOnAutoChargingMode = turnOnAutoChargingMode
        self.inhibitCharging = inhibitCharging
        self.forceDischarge = forceDischarge
        self.chargingStatus = chargingStatus
        self.enableSystemChargeLimit = enableSystemChargeLimit
    }

    public static var testValue: ChargingClient = unimplemented()
}

public extension DependencyValues {
    var chargingClient: ChargingClient {
        get { self[ChargingClient.self] }
        set { self[ChargingClient.self] = newValue }
    }
}
