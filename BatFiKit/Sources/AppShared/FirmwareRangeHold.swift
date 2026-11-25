//
//  FirmwareRangeHold.swift
//
//
//  Whether the firmware's charge band is holding charge on a battery below the limit.
//
//  Under `.firmwareRange` BatFi hands the firmware a band (`FirmwareChargeRange.band`) and
//  steps back. The firmware charges to the upper bound — the limit — and then holds while the
//  battery drifts down to the lower bound, where it charges again. BatFi's mode decision reads
//  `batteryLevel < limitInForce` as charging, so for the whole drift the menu said "Charging"
//  while nothing charged, and a green light keyed on `.inhibit` would have been dark most of
//  the time it should be lit. That is why the light used to be withheld on this backend.
//
//  This is the signal that closes the gap, and the only one: `ChargingManager` reports
//  `.inhibit` from it, and the MagSafe light follows that mode, so the two cannot disagree.
//
//  Decided from the SMC's power reading rather than IOKit's `isCharging`, which lags the SMC
//  by ~17 s into a charge and ~43 s out of one (`ChargeDirection`). The firmware's resume at
//  the lower bound is the edge that matters, and only the SMC sees it promptly.
//
//  In `AppShared` beside `SystemChargeHold`, its counterpart for Apple's limit, because
//  `AppCore` has no test target.
//

import Foundation
import Shared

public enum FirmwareRangeHold {
    /// Whether the firmware is holding charge inside its band right now.
    ///
    /// - Parameters:
    ///   - backend: the resolved backend, or nil where it is not known yet. Anything but
    ///     `.firmwareRange` answers false.
    ///   - limitInForce: the limit the helper applied — the band's upper bound. The lower
    ///     bound is derived from it, and from `resumeLevel`, exactly as the helper derived the
    ///     one it wrote.
    ///   - batteryPower: `PowerDistributionInfo.batteryPower`, or **nil where the helper could
    ///     not answer**. Nil is no evidence and answers false, which leaves the mode decision
    ///     where it was before this rule existed.
    ///   - batFiIsDischarging: BatFi's own `.forceDischarge`, which also reads as charge
    ///     leaving the battery and is not the firmware holding anything.
    ///   - resumeLevel: the resume level the band was handed with sailing in play, or nil for
    ///     today's band. The band is derived exactly as the helper wrote it
    ///     (`FirmwareChargeRange.band(forLimit:resumeLevel:)`), so with sailing the hold
    ///     reaches down to the resume level rather than five points under the limit.
    ///
    /// Both ends of the band are inside it. At the limit the battery is already `.inhibit`
    /// without this rule; at the lower bound the firmware has either resumed — and the SMC
    /// says so — or has not yet. Below the lower bound a battery that is not charging is not
    /// this hold (calibration, a hot battery, an adapter that cannot keep up), and keeps the
    /// label it had.
    ///
    /// Any reading that is not charge going in counts as held, including charge going *out*:
    /// a load burst the adapter cannot cover is drawn from the battery mid-drift, and the
    /// band is still what decides when charging resumes.
    public static func isHolding(
        backend: ChargeBackend?,
        chargerConnected: Bool,
        batteryLevel: Int,
        limitInForce: Int,
        batteryPower: Float?,
        batFiIsDischarging: Bool,
        resumeLevel: Int? = nil
    ) -> Bool {
        guard backend == .firmwareRange, chargerConnected, !batFiIsDischarging else { return false }
        guard let chargeIsFlowingIn = ChargeDirection.chargeIsFlowingIn(batteryPower: batteryPower),
              !chargeIsFlowingIn
        else { return false }
        return isInsideBand(batteryLevel: batteryLevel, limitInForce: limitInForce, resumeLevel: resumeLevel)
    }

    /// Whether `isHolding` could answer true for this battery, before its SMC reading is paid
    /// for. Callers ask this first so the round trip is only made inside the band.
    public static func isInsideBand(batteryLevel: Int, limitInForce: Int, resumeLevel: Int? = nil) -> Bool {
        let band = FirmwareChargeRange.band(forLimit: limitInForce, resumeLevel: resumeLevel)
        return (band.lower...band.upper).contains(batteryLevel)
    }
}
