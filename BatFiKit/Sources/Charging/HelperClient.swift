//
//  Charging.swift
//  BatFi
//
//  Created by Adam on 25/04/2023.
//

import Shared

public struct HelperClient {
    public var turnOnAutoChargingMode: (_ quitHelper: Bool) async throws -> Void
    public var inhibitCharging: (_ quitHelper: Bool) async throws -> Void
    public var forceDischarge: (_ quitHelper: Bool) async throws -> Void
    public var chargingStatus: (_ quitHelper: Bool) async throws -> SMCStatus
    public var quitChargingHelper: () async throws -> Void
}
