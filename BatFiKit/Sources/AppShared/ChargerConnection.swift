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
}
