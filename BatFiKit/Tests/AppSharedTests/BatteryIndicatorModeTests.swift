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
        systemIsDischargingToLimit: Bool = false,
        systemIsChargingPastLimit: Bool = false
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: nil,
            chargerConnected: chargerConnected,
            systemIsDischargingToLimit: systemIsDischargingToLimit,
            systemIsChargingPastLimit: systemIsChargingPastLimit
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

    /// The third thing `.inhibit` covers, and the one the icon was silent about: macOS
    /// charging past the limit. The plug sat over a *rising* percentage and the bolt — the
    /// only mark in the status item that means "charge is going in" — was missing for the
    /// whole top-up, because the mode is `.inhibit` and the old drain flag was true.
    @Test func aSystemTopUpPastTheLimitIsDrawnAsCharging() {
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(.inhibit, systemIsChargingPastLimit: true)
            ) == .charging
        )
    }

    /// The precedence in `stateDescription`, drawn. The two cannot both be true of a real
    /// reading; the icon must not depend on which flag it happens to test first.
    @Test func aTopUpOutranksADrainIfBothAreSomehowSet() {
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(
                    .inhibit,
                    systemIsDischargingToLimit: true,
                    systemIsChargingPastLimit: true
                )
            ) == .charging
        )
    }

    /// Off the charger nothing macOS does above a limit is in play, and the bolt would be a
    /// plain lie. Guards the early return the new branch sits below.
    @Test func aTopUpOffTheChargerIsStillDrawnAsDischarging() {
        #expect(
            BatteryIndicatorMode(
                appChargingMode: mode(
                    .inhibit,
                    chargerConnected: false,
                    systemIsChargingPastLimit: true
                )
            ) == .discharging
        )
    }
}
