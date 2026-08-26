//
//  ChargeDirection.swift
//
//
//  Which way charge is moving, from the two sources that can answer and that disagree.
//
//  Read by `SystemChargeDrain` and `SystemChargeTopUp`, which are exact complements above
//  the limit — one answers on `!isFlowingIn`, the other on `isFlowingIn` — so the two can
//  never both claim a reading, and above the limit one of them always does. That property is
//  the whole reason this is a function rather than a rule written out twice: a gate edited on
//  one side and not the other is how BatFi came to report a drain over a battery taking
//  477 mA.
//

import Foundation

public enum ChargeDirection {
    /// Whether charge is going *into* the battery right now.
    ///
    /// - Parameters:
    ///   - isCharging: `kIOPSIsChargingKey`. Free — it is already on every `PowerState` —
    ///     and it lags.
    ///   - chargeIsFlowingIn: the SMC's answer, `PowerDistributionInfo.batteryPower < 0`, or
    ///     **nil where it was not asked**. It costs an XPC round trip, so callers that have
    ///     not paid for one still get the IOKit answer rather than nothing.
    ///
    /// The SMC leads IOKit and only ever adds: measured ~17s on 26A5416b, where the SMC
    /// reported 46.2 W entering the battery while `AppleSmartBattery` still said 0 mA. So a
    /// `true` from the SMC settles it.
    ///
    /// A `false` from the SMC does not get to contradict IOKit's `true`. That is the same
    /// asymmetry `SystemChargeHold` applies, for the same reason: a battery resting at 0 mA
    /// and one whose SMC read is merely stale look identical from here, and only one of them
    /// is worth relabelling the menu over. The cost of the asymmetry is a top-up that keeps
    /// its label a few seconds into the drain that follows; the cost of dropping it is the
    /// bug this exists to fix, back again on every unreadable helper.
    public static func isFlowingIn(isCharging: Bool, chargeIsFlowingIn: Bool?) -> Bool {
        if chargeIsFlowingIn == true { return true }
        return isCharging
    }
}
