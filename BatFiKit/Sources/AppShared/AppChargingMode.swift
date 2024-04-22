//
//  AppChargingMode.swift
//
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public struct AppChargingMode: Equatable, Identifiable, CustomStringConvertible {
    public let mode: ChargingMode
    public let userTempOverride: UserTempChargingMode?
    public let chargerConnected: Bool

    public var id: String { "\(mode.id)\(userTempOverride?.id.description ?? "null")\(chargerConnected)" }

    public var description: String {
        """
        mode: \(mode.rawValue)
        userTempOverride: \(userTempOverride?.limit.description ?? "nil")
        chargerConnected: \(chargerConnected)
        """
    }

    public init(mode: ChargingMode, userTempOverride: UserTempChargingMode?, chargerConnected: Bool) {
        self.mode = mode
        self.userTempOverride = userTempOverride
        self.chargerConnected = chargerConnected
    }

}

public struct UserTempChargingMode: Equatable, Identifiable, RawRepresentable {
    public let limit: Int

    public var id: Int { limit }

    public var rawValue: Int { limit }

    public init(limit: Int) {
        self.limit = limit
    }

    public init?(rawValue: Int) {
        guard rawValue <= 100 && rawValue >= 0 else { return nil }
        self.init(rawValue: rawValue)
    }
}


public enum ChargingMode: String, Equatable, Identifiable {
    case initial
    case charging
    case inhibit
    case forceDischarge

    public var id: String { rawValue }
}
