//
//  Charging.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Shared

public struct ChargingClient {
    public var turnOnAutoChargingMode: () async throws -> Void
    public var inhibitCharging: () async throws -> Void
    public var forceDischarge: () async throws -> Void
    public var chargingStatus: () async throws -> SMCStatus
}
