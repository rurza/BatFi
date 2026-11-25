//
//  TempOverrideTargetReached.swift
//
//
//  Retiring an override the battery has reached, on a Mac that cannot hold it there.
//
//  Moved out of `ChargingManager` for the reason `TempOverrideDisconnectPolicy` was: `AppCore`
//  has no test target, and this rule is what used to make "Inhibit Charging" last one pass on
//  Apple's charge limit.
//

import Foundation
import Shared

public enum TempOverrideTargetReached {
    /// Whether `override` is retired because the battery has reached it.
    ///
    /// Symmetric to the charge-to-full removal, and needed for the same reason the discharge
    /// arm stopped reading the applied limit. Where charging is held at a percentage the
    /// inhibit writes nothing, and when this rule was written Apple's limit could not go
    /// below 80%: BatFi would discharge to the target, let Apple's limit charge it back, and
    /// discharge again — cycling the battery on mains power, which is precisely what BatFi
    /// exists to prevent. The override has met its goal, so it is retired rather than left
    /// oscillating. Backends that can pause on demand hold the target exactly; an unknown
    /// backend is treated as one, the default `ChargingManager` takes.
    ///
    /// The premise has since moved — `ManualChargeLimitDefaults` puts sub-80 limits in force
    /// under `.systemChargeLimit` — and one override is now exempt because of it: a manual
    /// inhibit held by freezing Apple's limit (`ManualInhibit.isHeldByFrozenLimit`). It is
    /// armed *at* the battery's level, so it has reached its target the moment it exists, and
    /// holding that level is the whole request. Other overrides keep the rule as it was;
    /// retiring it for them is a behaviour change of its own.
    ///
    /// `limit > 0` deliberately: "Run on Battery" is a 0% override and is meant to keep
    /// discharging until the charger is unplugged or the user cancels it. `limit < 100`:
    /// "Charge to 100%" has `ChargeToFullCompletion`.
    public static func retires(
        _ override: UserTempChargingMode,
        batteryLevel: Int,
        backend: ChargeBackend?
    ) -> Bool {
        guard batteryLevel <= override.limit, override.limit > 0, override.limit < 100 else { return false }
        let canPauseOnDemand = backend?.canPauseChargingOnDemand ?? true
        guard !canPauseOnDemand else { return false }
        return !ManualInhibit.isHeldByFrozenLimit(override, backend: backend)
    }
}
