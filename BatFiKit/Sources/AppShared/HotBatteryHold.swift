//
//  HotBatteryHold.swift
//
//
//  Stopping a hot battery from charging on a Mac whose charge limit is Apple's.
//
//  "Turn off charging when the battery is hot" is an inhibit on the SMC backends, and was
//  hidden and bypassed everywhere else: Apple's Manual Charge Limit has no "stop now", so on
//  `.systemChargeLimit` a battery at 63% and 45 °C charged on to its limit. It does not need
//  a "stop now". A limit set to the level the battery is at holds charge there just as well,
//  and BatFi already sets that limit on every pass — so the cutout on this backend is a
//  substitution into the requested limit, the way `ChargeToFullHold` is, and nothing else.
//
//  **The value is frozen for the whole episode.** Apple's limit costs a powerd adoption for
//  every change (about 45 s, during which charging carries on), so following the battery
//  each pass would mean the limit is always being adopted and never in force — and a battery
//  that crept up meanwhile would ratchet it upwards. One write in, one write out: raising the
//  limit back once the battery has cooled is itself a change, which is what re-arms charging.
//
//  **Never persisted, and that is what makes a crash safe.** The frozen value lives only in
//  `ChargingManager`'s memory and never reaches `Defaults[.chargeLimit]` or any other key. If
//  the app dies mid-episode, the helper's exit watcher restores system defaults, and the
//  relaunched app applies the user's own limit; if the battery is still hot then, the next
//  pass freezes afresh. Persisting it would be the way to strand a Mac at 63% for good.
//
//  Gauging is out of reach: while macOS charges up for calibration (`ChargingUpForGauging`)
//  it suspends its own limit policy, so no limit holds, this one included. That is not
//  fought — there is nothing to write that powerd would honour then.
//

import Foundation
import Shared

public enum HotBatteryHold {
    /// How far below the threshold the battery has to cool before the hold ends.
    ///
    /// Ending it at the line that starts it would release and refreeze on every flicker
    /// across 40 °C, and each release is a limit change that re-arms charging.
    public static let releaseMargin: Double = 2

    /// Whether this backend is held by freezing the limit.
    ///
    /// Only `.systemChargeLimit`: it can hold charge where the battery is
    /// (`canHoldChargeAtCurrentLevel`) and has no inhibit to do it with
    /// (`canPauseChargingOnDemand`). The inhibit backends keep their inhibit untouched. An
    /// unresolved backend is left to that existing path — which inhibits — rather than
    /// guessed at.
    public static func applies(to backend: ChargeBackend?) -> Bool {
        guard let backend else { return false }
        return backend.canHoldChargeAtCurrentLevel && !backend.canPauseChargingOnDemand
    }

    /// The frozen limit after this pass, or nil where nothing is held.
    ///
    /// - Parameters:
    ///   - frozen: the value held now, if any.
    ///   - isEnabled: the Charging pane setting, `temperatureSwitch`.
    ///   - temperature: `PowerState.batteryTemperature`, in °C. Nil ends a hold — a reading
    ///     that is not published can never show the battery cooling.
    ///   - threshold: `Constant.batteryTemperatureWarning`. Compared strictly, as
    ///     `HotBatteryProtection` does.
    ///   - chargerConnected: the resolved `ChargerConnection.isConnected`.
    ///   - batteryLevel: the state of charge this pass, which is what a new hold freezes.
    ///
    /// **The battery is frozen, not the lower of the battery and the limit.** The limit can
    /// be a discharge request — "Run on Battery" is a 0% override — and a value frozen from
    /// it would outlive the request: the user stops the discharge, the battery is still hot,
    /// and macOS drains it to 0% on mains power. `requestedLimit` takes the lower of the two
    /// on every pass instead, so a lower request wins only for as long as it stands.
    public static func next(
        frozenAt frozen: Int?,
        isEnabled: Bool,
        temperature: Double?,
        threshold: Double,
        chargerConnected: Bool,
        batteryLevel: Int,
        backend: ChargeBackend?
    ) -> Int? {
        guard applies(to: backend), isEnabled, chargerConnected, let temperature else { return nil }
        if let frozen {
            return temperature > threshold - releaseMargin ? frozen : nil
        }
        guard temperature > threshold else { return nil }
        return frozenLimit(batteryLevel: batteryLevel)
    }

    /// The limit to request: the lower of the frozen value and the one that would otherwise
    /// apply.
    ///
    /// Above everything that only ever asks for *more* — a "Charge to 100%" override, the
    /// charge-to-full hold — which is the precedence the cutout has always had on the inhibit
    /// backends. A lower request still wins: the user lowering the slider, or a discharge,
    /// which is fine for a hot battery.
    public static func requestedLimit(frozenAt frozen: Int?, otherwise limit: Int) -> Int {
        guard let frozen else { return limit }
        return min(frozen, limit)
    }

    /// Rounded *down* to a step of five from 80 up, where `setMCLLimit:` is the path that
    /// takes it. Only the value the hold invents is rounded; a user's own limit off the step
    /// still reaches the helper unchanged through `requestedLimit`. Down rather than up: up
    /// lets a hot battery charge a few more percent, down only lets macOS drain a few on mains
    /// power. Below 80 the charge-limit defaults take any value, so it is passed through —
    /// with no floor, because raising a hot battery's limit to one charges it.
    ///
    /// Also the value `ManualInhibit` arms, for the same reason: a pause rounded up is a
    /// pause that charges on.
    public static func frozenLimit(batteryLevel: Int) -> Int {
        guard batteryLevel >= 80 else { return batteryLevel }
        return batteryLevel - batteryLevel % 5
    }
}
