//
//  ManualInhibit.swift
//
//
//  "Inhibit Charging" — the status-menu command and its hotkey — on every backend.
//
//  The command has always been a temporary override at the battery's current level, and
//  everything that ends it is the override's own lifecycle: Stop Override (menu, hotkey or
//  Shortcuts), a different override replacing it, or the charger staying out for
//  `TempOverrideDisconnectPolicy.prolongedDisconnectTimeout`. That is unchanged here.
//
//  What changes is how the override is *held* under Apple's charge limit. That backend has
//  no inhibit, so the command was hidden there (MPX-41): `ChargingManager` retired any
//  override the battery had reached on a backend that cannot pause, and the "pause" lasted
//  one pass. But a limit at the battery's level holds charge there as well as an inhibit
//  would — the hot-battery hold already relies on it (`HotBatteryHold`). So on this backend
//  the inhibit override *is* the frozen limit: it flows into the requested limit like any
//  override, is exempt from that retirement, and is rounded the way the hot hold rounds.
//
//  **Never persisted beyond the override itself, which is in memory only.** A relaunch
//  starts with no override and applies the user's own limit; the helper's exit watcher puts
//  System Settings back if the app dies holding it. Nothing can strand the frozen value.
//
//  `.firmwareRange` and `.unsupported` stay without the command. The old objection under
//  `.firmwareRange` — a band at the current level let the battery fall five points and charged
//  it back — held only for the one-value call's fixed band; with the two-value call the lower
//  bound can sit anywhere, and sailing's hold uses exactly that (`FirmwareSailingHold`). Offering
//  the command there is a separate decision, not made yet.
//

import Foundation
import Shared

public enum ManualInhibit {
    /// Whether "Inhibit Charging" is offered — the menu item, the hotkey, and the Hotkeys
    /// row — on this backend.
    ///
    /// Exactly `canHoldChargeAtCurrentLevel`: the inhibit backends pause with their inhibit,
    /// Apple's charge limit holds by freezing the limit. **True while the backend is
    /// unknown**, the fail-open default the menu and the charging manager have always taken:
    /// withholding the command from a Mac that supports it because the first diagnostics
    /// call had not landed is the worse error.
    public static func isAvailable(on backend: ChargeBackend?) -> Bool {
        guard let backend else { return true }
        return backend.canHoldChargeAtCurrentLevel
    }

    /// What a pause would stop, as the menu and the hotkey offer it.
    public enum Pause: Equatable, Sendable {
        /// "Inhibit Charging": charge going in.
        case charging
        /// "Pause Discharging": charge coming out on the charger — macOS draining the battery
        /// to the limit, or BatFi's own discharge.
        case discharging
    }

    /// The pause the menu offers for `mode` on `backend`, or nil for none — and the hotkey
    /// follows it, so the two cannot disagree.
    ///
    /// Charging pauses charging, as it always has. Discharging *on the charger* pauses the
    /// discharge: BatFi's own (`.forceDischarge`), or macOS draining to the limit by itself
    /// (`.inhibit` with `systemIsDischargingToLimit`). Off the charger nothing can stop a
    /// battery powering the Mac, so nothing is offered. Nor while a pause is armed — "Resume
    /// Charging"/"Resume Discharging" is the command then — nor for anything else `.inhibit`
    /// covers: a hold is already a pause, and macOS charging past the limit for calibration
    /// is not BatFi's to pause.
    ///
    /// The backend rule is `isAvailable`, fail-open while the backend is unknown. And only
    /// where the pause would hold (`holds`), judged against `context` at `batteryLevel`; with
    /// either missing — before a pass has published a context, or with no reading — by the
    /// mode alone.
    public static func pauseOffered(
        for mode: AppChargingMode,
        backend: ChargeBackend?,
        context: PauseHoldContext? = nil,
        batteryLevel: Int? = nil
    ) -> Pause? {
        guard let pause = pauseByMode(mode, backend: backend) else { return nil }
        if let context, let batteryLevel,
           !holds(pause, batteryLevel: batteryLevel, context: context, backend: backend) {
            return nil
        }
        return pause
    }

    /// Whether a `pause` armed with the battery at `batteryLevel` would hold it there.
    ///
    /// The inhibit backends hold the exact level with their own inhibit, always. Under Apple's
    /// charge limit the pause *is* a limit, and what holds is the limit the apply will put in
    /// force — the frozen level raised to this Mac's floor, where macOS has no path below 80
    /// (`ChargingAheadOfApply.willApply`):
    ///
    /// - Above the battery, it charges it: a pause at 60% applied as 80 charged to 80 under
    ///   "Discharging paused at 60%". Not offered, for either pause.
    /// - For a discharge, at or below the target the discharge is heading to
    ///   (`dischargeTarget`), it stops nothing: limit 80, battery 84, frozen at 80 — the
    ///   percentage went on falling under "paused". Not offered. Judged against the target, not
    ///   the limit powerd enforces: that lags a change by up to 45 s, and right after Resume it
    ///   is still the old frozen value, which refused a quick re-pause.
    public static func holds(
        _ pause: Pause,
        batteryLevel: Int,
        context: PauseHoldContext,
        backend: ChargeBackend?
    ) -> Bool {
        let held = override(batteryLevel: batteryLevel, backend: backend)
        guard held.isInhibit, HotBatteryHold.applies(to: backend) else { return true }
        let applied = ChargingAheadOfApply.willApply(requested: held.limit, floor: context.floor)
        guard applied <= batteryLevel else { return false }
        if pause == .discharging, let target = context.dischargeTarget, applied <= target {
            return false
        }
        return true
    }

    /// The limit a discharge on the charger is heading to: a plain override's own — BatFi's
    /// discharge under "Run on Battery" or a Shortcuts limit runs to the request, not to what
    /// Apple's limit could express — and otherwise the limit the pass requests with no
    /// override, as the apply will put it in force, which is what macOS drains to. An armed
    /// pause is not a target: the target is what ending it would resume.
    public static func dischargeTarget(
        overrideInForce: UserTempChargingMode?,
        resumedLimit: Int,
        floor: Int?
    ) -> Int {
        if let overrideInForce, !overrideInForce.isInhibit {
            return overrideInForce.limit
        }
        return ChargingAheadOfApply.willApply(requested: resumedLimit, floor: floor)
    }

    private static func pauseByMode(_ mode: AppChargingMode, backend: ChargeBackend?) -> Pause? {
        guard mode.chargerConnected,
              isAvailable(on: backend),
              mode.userTempOverride?.isInhibit != true
        else { return nil }
        switch mode.mode {
        case .charging:
            return .charging
        case .forceDischarge:
            return .discharging
        case .inhibit:
            guard mode.systemIsDischargingToLimit, !mode.systemIsChargingPastLimit else { return nil }
            return .discharging
        case .initial:
            return nil
        }
    }

    /// The override the pause offered for `mode` arms with the battery at `batteryLevel`, or
    /// nil where none is offered (`pauseOffered`).
    ///
    /// A discharge pause remembers that it is one, and the plain override it replaces — "Run
    /// on Battery", a Shortcuts limit — so that "Resume Discharging" puts that discharge back
    /// rather than ending in the charge limit's policy, which can be a charge.
    ///
    /// Judged at `batteryLevel`, the click's own reading, against `context`: a click where the
    /// pause would not hold arms nothing. With no context, by the mode alone.
    public static func pause(
        for mode: AppChargingMode,
        batteryLevel: Int,
        backend: ChargeBackend?,
        context: PauseHoldContext? = nil
    ) -> UserTempChargingMode? {
        guard let pause = pauseOffered(for: mode, backend: backend, context: context, batteryLevel: batteryLevel)
        else { return nil }
        let held = override(batteryLevel: batteryLevel, backend: backend)
        guard pause == .discharging, held.isInhibit else { return held }
        let replaced = mode.userTempOverride.flatMap { $0.isInhibit ? nil : $0.limit }
        return UserTempChargingMode(
            limit: held.limit,
            isInhibit: true,
            pausesDischarge: true,
            resumesOverrideLimit: replaced
        )
    }

    /// The override "Inhibit Charging" arms with the battery at `batteryLevel`.
    ///
    /// The level itself on the inhibit backends, as it always has been. Under Apple's charge
    /// limit the level as `HotBatteryHold` freezes it: from 80 up `setMCLLimit:` rounds an
    /// off-step value *up*, so 87 would charge on to 90; rounded down to 85 macOS drains two
    /// points instead. The rounded value is the override's own limit, so the menu's
    /// "temporarily set to 85%" names the value System Settings shows.
    ///
    /// **An unknown backend is not guessed at, and arms a plain override.** Its level is not
    /// rounded, so if it were marked an inhibit and the backend later resolved to Apple's
    /// limit, 87 would be exempt from retirement while `setMCLLimit:` rounded it up to 90 —
    /// the battery charging under a "pause". Plain, it is held exactly on the inhibit
    /// backends, as it always was, and retired after a pass on Apple's limit, as it was
    /// before this existed: the safe failure for a click in the first seconds after launch.
    public static func override(batteryLevel: Int, backend: ChargeBackend?) -> UserTempChargingMode {
        guard let backend else { return UserTempChargingMode(limit: batteryLevel) }
        let limit = HotBatteryHold.applies(to: backend)
            ? HotBatteryHold.frozenLimit(batteryLevel: batteryLevel)
            : batteryLevel
        return UserTempChargingMode(limit: limit, isInhibit: true)
    }

    /// Whether `override` is an inhibit held by freezing Apple's charge limit — the case
    /// `ChargingManager` treats like a hot-battery hold: exempt from the reached-target
    /// retirement, no discharge of BatFi's own toward a rounded-down value (macOS drains to
    /// it itself), no "limit not holding" warning naming it as the user's limit, and no
    /// resume-stall nudge raising it.
    ///
    /// The same backend rule as `HotBatteryHold.applies`, so the two holds can never
    /// disagree about which Macs freeze the limit.
    public static func isHeldByFrozenLimit(_ override: UserTempChargingMode?, backend: ChargeBackend?) -> Bool {
        guard let override, override.isInhibit else { return false }
        return HotBatteryHold.applies(to: backend)
    }

    /// The level `mode` is paused at, or nil when no inhibit is armed on a connected charger.
    ///
    /// **Paused from the click**, whatever the mode underneath and on every backend. Under
    /// Apple's charge limit powerd takes up to a minute to adopt the frozen limit, and the
    /// battery charges on meanwhile, but the state the user asked for is the one shown —
    /// and held through that window (`ChargeLimitRaiseWindow`). It used to read "Pausing
    /// charging…" until powerd confirmed it; the owner wants every change shown at once. The
    /// inhibit backends write their inhibit on the pass after the click, so for them nothing
    /// changes but a moment.
    public static func pausedLimit(of mode: AppChargingMode) -> Int? {
        guard mode.chargerConnected,
              let override = mode.userTempOverride,
              override.isInhibit
        else { return nil }
        return override.limit
    }
}

/// What a pause armed now is judged against (`ManualInhibit.holds`). Published by the charging
/// pass for the menu, apart from the published charging state: it changes with no change of
/// state anyone is told about, and nothing that follows the state should hear of it.
public struct PauseHoldContext: Equatable, Sendable {
    /// The limit a discharge on the charger is heading to (`ManualInhibit.dischargeTarget`), or
    /// nil where it is not known.
    public let dischargeTarget: Int?
    /// The floor this Mac applies a sub-80 request at, or nil where none was seen
    /// (`ChargingAheadOfApply.learnedFloor`).
    public let floor: Int?

    public init(dischargeTarget: Int?, floor: Int?) {
        self.dischargeTarget = dischargeTarget
        self.floor = floor
    }
}
