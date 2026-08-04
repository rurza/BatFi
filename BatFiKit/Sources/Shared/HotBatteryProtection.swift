//
//  HotBatteryProtection.swift
//
//
//  What "stop charging when the battery is hot" should do on this pass.
//
//  A three-line `if` until Phase 1 made `PowerState.batteryTemperature` optional, at which
//  point one of its arms became unreachable and nothing said so. Here, as a value, for the
//  same reason `AppliedChargeLimit` and `ChargeControlDisclosure` are: the case that has to
//  be right is the one nobody can produce on demand, and `Shared` is the only module the
//  test target can reach.
//

import Foundation

public enum HotBatteryProtection {
    public enum Decision: Equatable, Sendable {
        /// The user has the setting off. Nothing to do and nothing to say.
        case notEnabled

        /// The setting is on, the temperature was read, and it is under the threshold.
        case withinLimits

        /// The setting is on and the battery is over the threshold. Hold charging.
        case tooHot(temperature: Double)

        /// **The setting is on and there is no temperature to check it against.**
        ///
        /// Its own case rather than folded into `withinLimits`, because the difference is
        /// the whole finding. Before Phase 1 a missing temperature threw out of the power
        /// source read, the stream yielded nothing and BatFi wrote no SMC state at all —
        /// so the feature failed closed, by doing nothing. Now BatFi goes on managing
        /// charging normally with the cutout permanently and invisibly bypassed: the
        /// Advanced pane toggle still reads ON, `BatteryInfoView` just hides the
        /// temperature row, and the missing-property dump only fires for the three
        /// *required* fields.
        ///
        /// Nothing can be done about it — a temperature that is not published cannot be
        /// invented — so what this case buys is that it is *said*, once, in the log and in
        /// the analytics breadcrumb. A safety feature that has stopped working has to be
        /// visible in the bug report from the Mac it stopped working on.
        case cutoutCannotFire
    }

    /// - Parameters:
    ///   - isEnabled: the Advanced pane setting. Defaults to **true**, which is why the
    ///     `cutoutCannotFire` arm is not a corner case.
    ///   - temperature: `PowerState.batteryTemperature`, in °C, or nil where this
    ///     firmware publishes neither `VirtualTemperature` nor `Temperature`.
    ///   - threshold: `Constant.batteryTemperatureWarning`.
    public static func decision(isEnabled: Bool, temperature: Double?, threshold: Double) -> Decision {
        guard isEnabled else { return .notEnabled }
        guard let temperature else { return .cutoutCannotFire }
        return temperature > threshold ? .tooHot(temperature: temperature) : .withinLimits
    }
}
