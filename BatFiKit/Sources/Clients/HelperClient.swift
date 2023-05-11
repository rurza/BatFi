//
//  Charging.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Dependencies
import Shared

public struct HelperClient: TestDependencyKey {
    public var turnOnAutoChargingMode: (_ quitHelper: Bool) async throws -> Void
    public var inhibitCharging: (_ quitHelper: Bool) async throws -> Void
    public var forceDischarge: (_ quitHelper: Bool) async throws -> Void
    public var chargingStatus: (_ quitHelper: Bool) async throws -> SMCStatus
    public var quitChargingHelper: () async throws -> Void

    public init(
        turnOnAutoChargingMode: @escaping (Bool) async throws -> Void,
        inhibitCharging: @escaping (Bool) async throws -> Void,
        forceDischarge: @escaping (Bool) async throws -> Void,
        chargingStatus: @escaping (Bool) async throws -> SMCStatus,
        quitChargingHelper: @escaping () async throws -> Void
    ) {
        self.turnOnAutoChargingMode = turnOnAutoChargingMode
        self.inhibitCharging = inhibitCharging
        self.forceDischarge = forceDischarge
        self.chargingStatus = chargingStatus
        self.quitChargingHelper = quitChargingHelper
    }

    public static var testValue: HelperClient = unimplemented()
}

extension DependencyValues {
    public var helperClient: HelperClient {
        get { self[HelperClient.self] }
        set { self[HelperClient.self] = newValue }
    }
}
