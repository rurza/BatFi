//
//  BatteryIndicatorMode.swift
//
//
//  What the status item draws, derived from what the app last told the hardware.
//
//  Here rather than in `BatteryIndicator` for the reason `SystemChargeDrain` is here: the
//  view module has no test target, and this is a mapping that has already been wrong once.
//

import Foundation

/// The symbol the battery indicator draws over the battery.
public enum BatteryIndicatorMode: Hashable, Sendable {
    /// A bolt: charge is going in.
    case charging
    /// Nothing: charge is coming out, on the charger or off it.
    case discharging
    /// A plug (a pause, in the percentage indicator): charge is being held by BatFi.
    case inhibited
    /// An exclamation mark: no mode has been reported yet.
    case error

    public init(appChargingMode: AppChargingMode) {
        guard appChargingMode.mode != .initial else {
            self = .error
            return
        }
        guard appChargingMode.chargerConnected else {
            self = .discharging
            return
        }
        switch appChargingMode.mode {
        case .charging:
            self = .charging
        case .inhibit:
            // `.inhibit` is the mode on both sides of a line the icon has to draw
            // differently. Where the mechanism owns the charging decision, macOS drains the
            // battery down to the limit itself and BatFi writes no inhibit at all — so the
            // plug, which says charging is paused, sits over a falling percentage. The
            // battery is doing there exactly what it does under `.forceDischarge`, and is
            // drawn the same.
            self = appChargingMode.systemIsDischargingToLimit ? .discharging : .inhibited
        case .forceDischarge:
            self = .discharging
        case .initial:
            self = .error
        }
    }
}
