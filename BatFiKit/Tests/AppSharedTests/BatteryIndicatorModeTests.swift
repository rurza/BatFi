//
//  BatteryIndicatorModeTests.swift
//  BatFi
//
//  The status item has three things to say and `.inhibit` covers two of them. Where the
//  charge mechanism owns the charging decision, macOS drains the battery down to the limit
//  itself, BatFi writes no inhibit, and the mode it records is `.inhibit` all the same —
//  so a plug drawn straight from the mode says "paused" over a battery the user can watch
//  fall.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct BatteryIndicatorModeTests {
    private func mode(
        _ mode: ChargingMode,
        chargerConnected: Bool = true,
        systemIsDischargingToLimit: Bool = false
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: nil,
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: systemIsDischargingToLimit
        )
    }

    /// The one the label already gets right.
    @Test func aSystemDrainToTheLimitIsDrawnAsDischarging() {
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(.inhibit, systemIsDischargingToLimit: true)
            ) == .discharging
        )
    }

    /// The other half of `.inhibit`: BatFi holding charge on firmware that pauses on demand.
    @Test func aPauseBatFiIsMakingIsDrawnAsInhibited() {
        #expect(BatteryIndicatorMode(appChargingMode: mode(.inhibit)) == .inhibited)
    }

    /// The drain BatFi asks for and the drain macOS performs look the same on the battery,
    /// and are drawn the same.
    @Test func forceDischargeOnTheChargerIsDrawnAsDischarging() {
        #expect(BatteryIndicatorMode(appChargingMode: mode(.forceDischarge)) == .discharging)
    }

    @Test func chargingIsDrawnAsCharging() {
        #expect(BatteryIndicatorMode(appChargingMode: mode(.charging)) == .charging)
    }

    /// Off the charger nothing is being held, whatever the last mode was and whatever the
    /// drain flag last said.
    @Test func anUnpluggedMacIsDrawnAsDischarging() {
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(.inhibit, chargerConnected: false)
            ) == .discharging
        )
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(.charging, chargerConnected: false)
            ) == .discharging
        )
    }

    /// No mode reported yet is not a battery state, and it outranks the charger.
    @Test func theInitialModeIsAnError() {
        #expect(BatteryIndicatorMode(appChargingMode: mode(.initial)) == .error)
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(.initial, chargerConnected: false)
            ) == .error
        )
    }
}
