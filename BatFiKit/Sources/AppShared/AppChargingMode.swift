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

    /// Whether macOS is holding charge on a battery that sits **below** the limit.
    ///
    /// The other half of what `.inhibit` covers on a mechanism that owns the charging
    /// decision, and it is here for the same reasons `systemIsDischargingToLimit` is: BatFi
    /// did not ask for it, issues no write while it lasts, and cannot currently end it —
    /// re-writing the same limit does not re-open the charge session macOS closed.
    ///
    /// Mutually exclusive with the drain in practice, because that one needs the battery
    /// above the limit and this one needs it below. The struct cannot express that; the
    /// precedence lives in `stateDescription` and is pinned by a test.
    ///
    /// **Defaults to `false`, meaning "not known to be held"** — the same reading the drain
    /// flag gets. `ChargingManager` is the one place that knows the level, the limit in
    /// force, the firmware's attribution and the backend at the same moment.
    public let systemIsHoldingBelowLimit: Bool

    /// Whether macOS is charging the battery **past** the limit, on its own.
    ///
    /// The third thing `.inhibit` covers on a mechanism that owns the charging decision, and
    /// here for the same reasons the other two are: Apple's charge limit occasionally charges
    /// to 100% to keep its state-of-charge estimate honest, BatFi's limit stays in force
    /// throughout, and BatFi issues no write and cannot stop it. See `SystemChargeTopUp`.
    ///
    /// Mutually exclusive with the drain by construction rather than in practice — the two
    /// read one direction rule and negate it — and with the hold, which needs the battery
    /// below the limit. The struct still cannot express that; the precedence lives in
    /// `stateDescription` and is pinned by a test.
    ///
    /// **Defaults to `false`, meaning "not known to be charging past the limit"** — the same
    /// reading the other two flags get, and erring the same way: it costs the plain inhibit
    /// label on a Mac being topped up, where claiming a top-up by default would put "macOS is
    /// charging to 100%" on every Mac holding its limit correctly.
    public let systemIsChargingPastLimit: Bool

    public var id: String {
        "\(mode.id)\(userTempOverride?.id.description ?? "null")\(chargerConnected)\(systemIsDischargingToLimit)\(systemIsHoldingBelowLimit)\(systemIsChargingPastLimit)"
    }

    public var description: String {
        """
        mode: \(mode.rawValue)
        userTempOverride: \(userTempOverride?.limit.description ?? "nil")
        chargerConnected: \(chargerConnected)
        systemIsDischargingToLimit: \(systemIsDischargingToLimit)
        systemIsHoldingBelowLimit: \(systemIsHoldingBelowLimit)
        systemIsChargingPastLimit: \(systemIsChargingPastLimit)
        """
    }

    public init(
        mode: ChargingMode,
        userTempOverride: UserTempChargingMode?,
        chargerConnected: Bool,
        systemIsDischargingToLimit: Bool = false,
        systemIsHoldingBelowLimit: Bool = false,
        systemIsChargingPastLimit: Bool = false
    ) {
        self.mode = mode
        self.userTempOverride = userTempOverride
        self.chargerConnected = chargerConnected
        self.systemIsDischargingToLimit = systemIsDischargingToLimit
        self.systemIsHoldingBelowLimit = systemIsHoldingBelowLimit
        self.systemIsChargingPastLimit = systemIsChargingPastLimit
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
