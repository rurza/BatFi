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
            // `.inhibit` is the mode on all three sides of a line the icon has to draw
            // differently, because where the mechanism owns the charging decision BatFi
            // writes no inhibit at all and the battery does as macOS pleases.
            //
            // Draining to the limit: the plug, which says charging is paused, would sit over
            // a falling percentage. The battery is doing exactly what it does under
            // `.forceDischarge`, and is drawn the same.
            //
            // Charging past the limit: the plug sat over a *rising* percentage, and the bolt
            // — the one thing in the status item that means "charge is going in" — was
            // missing for the whole top-up. Same mode, opposite direction, and the icon has
            // to follow the battery rather than the mode. Checked first, matching the
            // precedence in `stateDescription`.
            if appChargingMode.systemIsChargingPastLimit {
                self = .charging
                return
            }
            self = appChargingMode.systemIsDischargingToLimit ? .discharging : .inhibited
        case .forceDischarge:
            self = .discharging
        case .initial:
            self = .error
        }
    }
}
