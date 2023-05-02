//
//  Charging.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

public struct ChargingClient {
    public var turnOnAutoChargingMode: () async throws -> Void
    public var turnOffCharging: () async throws -> Void
}
