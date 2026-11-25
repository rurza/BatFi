//
//  FirmwareRangeDischarge.swift
//
//
//  Which override a pass works its requested limit out from under `.firmwareRange`.
//
//  "Run on Battery" is an override at 0%. Everywhere else that 0 is a request the backend
//  handles, but under `.firmwareRange` it became the band's limit: a 0–0 band, whose sequence
//  disarmed the band (`bfF0 = 0`) and then had its first bound refused by the SMC. The band
//  was off for the whole discharge, the failing write repeated every pass, and when the
//  discharge ended the band was armed again from scratch — after which the firmware charged a
//  battery that sat inside the sailing band and was labelled as held.
//
//  The discharge itself is BatFi's own (`CHIE`) and the mode decision reads it from the
//  override, not from the limit applied, so it needs nothing from the band. The band is left
//  exactly as it would be without the override — the same limit and resume level — so the
//  helper's needs-write record holds and nothing is written when the discharge starts or ends.
//
//  In `AppShared` because `AppCore` has no test target.
//

import Foundation
import Shared

public enum FirmwareRangeDischarge {
    /// The override the pass's requested limit — and the sailing levels that go with it —
    /// are worked out from: nil, as if none were in force, for an override the firmware band
    /// cannot hold under `.firmwareRange`; otherwise `override` itself.
    ///
    /// Only the limit and the band are worked out from this. The mode decision, the override's
    /// own bookkeeping and the sailing phase tracker go on reading the real override.
    ///
    /// Every other backend, and an unknown one, gets the override unchanged: under Apple's
    /// limit and the inhibit backends a 0% request is one those paths already handle.
    public static func overrideForLimit(_ override: UserTempChargingMode?, backend: ChargeBackend?) -> UserTempChargingMode? {
        guard let override, backend == .firmwareRange, !FirmwareChargeRange.canHold(limit: override.limit) else {
            return override
        }
        return nil
    }
}
