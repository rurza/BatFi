//
//  AppChargingMode.swift
//
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public struct AppChargingMode: Equatable, Identifiable, CustomStringConvertible, Sendable {
    public let mode: ChargingMode
    public let userTempOverride: UserTempChargingMode?
    public let chargerConnected: Bool

    /// Whether macOS is draining the battery down to the limit right now, on its own.
    ///
    /// Not a fourth `ChargingMode`. `ChargingMode` is what BatFi last *told the hardware*,
    /// and this is the opposite: a state BatFi did not ask for and cannot stop — the
    /// `drain: true` in the `ChargeCtrlPolicy` behind Apple's Manual Charge Limit, which is
    /// exposed only behind an Apple-private entitlement. Making it a mode would put it in
    /// front of `shouldApply` and the appliers, which decide what to write, and there is no
    /// write.
    ///
    /// It exists because `.inhibit` is the honest mode for "charge is being held, just not
    /// by me" and the honest *label* for it is a different sentence. A user watching 61%
    /// fall toward a 55% limit while the menu reads "Inhibiting charging" is being told
    /// something they can see is false, and the mechanism that makes it false is the same
    /// one `ChargeBackend.dischargesToLimitItself` names.
    ///
    /// **Defaults to `false`, which means "not known to be draining" rather than "holding
    /// steady".** Every construction site that has not worked the answer out — the initial
    /// state, the helper's status read, a charger-connection update — leaves it alone, and
    /// `ChargingManager` is the one place that knows the battery level, the limit actually
    /// in force and the backend at the same moment. Erring this way costs the old label on
    /// a Mac that is draining; erring the other way would claim a drain on every Mac that
    /// is not.
    public let systemIsDischargingToLimit: Bool

    public var id: String {
        "\(mode.id)\(userTempOverride?.id.description ?? "null")\(chargerConnected)\(systemIsDischargingToLimit)"
    }

    public var description: String {
        """
        mode: \(mode.rawValue)
        userTempOverride: \(userTempOverride?.limit.description ?? "nil")
        chargerConnected: \(chargerConnected)
        systemIsDischargingToLimit: \(systemIsDischargingToLimit)
        """
    }

    public init(
        mode: ChargingMode,
        userTempOverride: UserTempChargingMode?,
        chargerConnected: Bool,
        systemIsDischargingToLimit: Bool = false
    ) {
        self.mode = mode
        self.userTempOverride = userTempOverride
        self.chargerConnected = chargerConnected
        self.systemIsDischargingToLimit = systemIsDischargingToLimit
    }

}

public struct UserTempChargingMode: Equatable, Identifiable, RawRepresentable, Sendable {
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


public enum ChargingMode: String, Equatable, Identifiable, Sendable {
    case initial
    case charging
    case inhibit
    case forceDischarge

    public var id: String { rawValue }
}
