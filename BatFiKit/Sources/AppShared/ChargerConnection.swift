//
//  ChargerConnection.swift
//
//
//  Whether to act as though the charger is plugged in.
//
//  A separate question from what IOKit reported, because the fallback used when
//  `ExternalConnected` is missing — "the power source string says AC Power" — is wrong in
//  precisely the situation BatFi creates for itself.
//

import Foundation

public enum ChargerConnection {
    /// - Parameters:
    ///   - reported: `PowerState.chargerConnected`.
    ///   - isDerived: `PowerState.chargerConnectionIsDerived`.
    ///   - appMode: the mode BatFi believes it is in.
    ///
    /// Force-discharge isolates the adapter, so IOPS reports "Battery Power" while the
    /// charger is still physically connected. On firmware that publishes
    /// `ExternalConnected` this never surfaces — the precise signal is used. On firmware
    /// that has dropped it, the first read derives `true`, `turnOnDischarging` engages
    /// `CHIE`, and the *second* read derives `false`. Three things then go wrong at once:
    /// `turnOnDischarging` hits its `guard chargerConnected` and returns before
    /// re-asserting a discharge it is still running, `setUpDelaySleep` releases the sleep
    /// assertion mid-discharge so the Mac can auto-sleep with force-discharge latched in
    /// the SMC, and the status item reports "not connected" while it is.
    ///
    /// Narrow on purpose. A *reported* disconnection is always believed, and a derived one
    /// is only overridden in the one mode that explains it. Everywhere else a derived
    /// "battery power" really does mean the charger came out.
    public static func isConnected(reported: Bool, isDerived: Bool, appMode: ChargingMode) -> Bool {
        if reported { return true }
        return isDerived && appMode == .forceDischarge
    }

    /// Whether the Mac is running on its battery: the one answer every feature that acts
    /// "on battery" asks, so that none of them can disagree about it.
    ///
    /// Exactly `!isConnected(…)`, parameters included — so BatFi's own force discharge,
    /// which reads as battery power on derived firmware, does not count, while the charger
    /// actually coming out during one does.
    public static func isOnBattery(reported: Bool, isDerived: Bool, appMode: ChargingMode) -> Bool {
        !isConnected(reported: reported, isDerived: isDerived, appMode: appMode)
    }

    /// The connection to publish ahead of the charge-limit apply, or nil when the published
    /// state already says it.
    ///
    /// The apply can wait up to 45 s for powerd on macOS 27, and the first pass after every
    /// plug-in or unplug pays it, so without this the icon kept showing the old connection
    /// for that long. Only a *change* is published, so a pass that leaves the connection as
    /// it was never marks a known mode as pending; and nothing before the first mode, which
    /// has no connection to speak of. See `AppChargingMode.isAwaitingModeForChargerChange`.
    public static func connectionToPublishAheadOfMode(published: AppChargingMode, resolved: Bool) -> Bool? {
        guard published.mode != .initial, published.chargerConnected != resolved else { return nil }
        return resolved
    }

    /// Whether a state rebuilt from the helper's status read — on wake, on a display change,
    /// for the first mode — is still ahead of its mode.
    ///
    /// That read builds the whole state afresh, and the mark defaulted to off. A
    /// power-supplying USB-C display fires a power-source change and a screen change
    /// together: the main pass published the plug-in ahead of its mode and sat in the apply,
    /// and the screen handler's read cleared the mark with the helper's raw mode in hand, so
    /// the banner announced that mode and then the derived one. While a publish ahead of the
    /// mode for this same connection is outstanding the mark stays; only an applier clears
    /// it. A different connection is a new change, and `.initial` is never published ahead,
    /// so the first mode of the session stays announceable.
    public static func isAwaitingModeAfterFetch(published: AppChargingMode, fetchedConnected: Bool) -> Bool {
        published.isAwaitingModeForChargerChange && published.chargerConnected == fetchedConnected
    }
}
