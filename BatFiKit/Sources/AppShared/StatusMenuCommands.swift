//
//  StatusMenuCommands.swift
//
//
//  Which commands the status menu may offer on this Mac.
//
//  Here rather than in the menu builder for the reason `TempOverrideDisconnectPolicy` is:
//  `AppCore` has no test target, and a rule that decides whether a user is shown a button
//  that does nothing is worth pinning.
//

import Foundation
import L10n
import Shared

public enum StatusMenuCommands {
    /// Whether "Inhibit Charging" — or "Pause Discharging", its twin for a battery
    /// discharging on the charger — should appear.
    ///
    /// - Parameter backend: this Mac's charge backend, or nil while it is unknown. Whether
    ///   it can hold charge is `ManualInhibit.isAvailable(on:)`, which the hotkey and the
    ///   Hotkeys row ask too — **true while the backend is unknown**: withholding the
    ///   command from a Mac that supports it because the first diagnostics call had not
    ///   landed is the worse of the two errors.
    ///
    /// Offered wherever the Mac can hold charge at its current level: by its own inhibit, or
    /// under Apple's charge limit by freezing the limit there (`ManualInhibit`). Not under
    /// `.firmwareRange` or `.unsupported`, where the command would report success and pause
    /// nothing. Not while an inhibit is armed: under Apple's charge limit the mode can stay
    /// `.charging` while the frozen limit is applied, and a second click would only re-arm
    /// the same pause; "Resume Charging" is the command that applies then. The whole rule is
    /// `ManualInhibit.pauseOffered`, which the hotkey asks too.
    public static func showsInhibitCharging(
        mode: AppChargingMode,
        backend: ChargeBackend?,
        context: PauseHoldContext? = nil,
        batteryLevel: Int? = nil
    ) -> Bool {
        ManualInhibit.pauseOffered(for: mode, backend: backend, context: context, batteryLevel: batteryLevel) != nil
    }

    /// The title of the pause command for `mode`, or nil where none is offered: "Inhibit
    /// Charging" while charging, "Pause Discharging" while the battery discharges on the
    /// charger. Only where the pause would hold, judged against `context` at `batteryLevel`
    /// (`ManualInhibit.holds`).
    public static func pauseTitle(
        mode: AppChargingMode,
        backend: ChargeBackend?,
        context: PauseHoldContext? = nil,
        batteryLevel: Int? = nil
    ) -> String? {
        switch ManualInhibit.pauseOffered(for: mode, backend: backend, context: context, batteryLevel: batteryLevel) {
        case .charging: L10n.Menu.Label.inhibitCharging
        case .discharging: L10n.Menu.Label.pauseDischarging
        case nil: nil
        }
    }

    /// The title of the button that ends `override`.
    ///
    /// "Resume Charging" for one armed by "Inhibit Charging", "Resume Discharging" for one
    /// armed by "Pause Discharging", on every backend — it is a pause everywhere the command
    /// is offered. "Stop Override" for the rest: Shortcuts limits and anything else that is
    /// not 0 or 100, which have their own menu items.
    public static func stopOverrideTitle(for override: UserTempChargingMode) -> String {
        guard override.isInhibit else { return L10n.Menu.Label.stopOverride }
        return override.pausesDischarge ? L10n.Menu.Label.resumeDischarging : L10n.Menu.Label.resumeCharging
    }

    /// Whether the menu shows a button that ends `override`.
    ///
    /// Always for a pause, whatever its level: a discharge paused at 100% is no "Charge to
    /// 100%", and that item's checkmark is the only other way out of a 100% override.
    public static func showsStopOverride(for override: UserTempChargingMode) -> Bool {
        override.isInhibit || (override.limit != 0 && override.limit != 100)
    }

    /// Whether `override` is "Charge to 100%", which ticks that item. Not a pause at 100%.
    public static func isChargeToFull(_ override: UserTempChargingMode?) -> Bool {
        guard let override, !override.isInhibit else { return false }
        return override.limit == 100
    }

    /// Whether `override` is "Run on Battery", which ticks that item. Not a pause at 0%.
    public static func isRunOnBattery(_ override: UserTempChargingMode?) -> Bool {
        guard let override, !override.isInhibit else { return false }
        return override.limit == 0
    }
}
