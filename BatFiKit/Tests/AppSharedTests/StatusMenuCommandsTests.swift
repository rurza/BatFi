//
//  StatusMenuCommandsTests.swift
//  BatFi
//
//  Which commands the status menu may offer. The rule that matters here is the one the
//  menu never had: "Inhibit Charging" writes nothing on firmware whose mechanism holds
//  charge at a percentage, so offering it there is a button that reports success and
//  changes nothing the user asked to change.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct StatusMenuCommandsTests {
    private func mode(
        _ mode: ChargingMode,
        override: Int? = nil,
        chargerConnected: Bool = true
    ) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: override.map(UserTempChargingMode.init(limit:)),
            chargerConnected: chargerConnected
        )
    }

    // MARK: - Macs whose firmware can pause charging on demand

    @Test func offeredWhileChargingOnAMacThatCanPause() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                chargingCanBePausedOnDemand: true
            )
        )
    }

    @Test func offeredWhileForceDischargingOnAMacThatCanPause() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.forceDischarge),
                chargingCanBePausedOnDemand: true
            )
        )
    }

    // MARK: - Macs whose mechanism holds charge at a percentage

    /// The reported bug: "Run on Battery" is engaged, so the menu offers "Inhibit
    /// Charging" beside it — on firmware where the inhibit write is a no-op.
    @Test func withheldWhileForceDischargingOnAMacThatCannotPause() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.forceDischarge),
                chargingCanBePausedOnDemand: false
            ) == false
        )
    }

    @Test func withheldWhileChargingOnAMacThatCannotPause() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                chargingCanBePausedOnDemand: false
            ) == false
        )
    }

    // MARK: - Rules that predate the backend gate

    @Test func withheldWhileTheChargerIsOut() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging, chargerConnected: false),
                chargingCanBePausedOnDemand: true
            ) == false
        )
    }

    @Test func withheldWhileAlreadyInhibiting() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.inhibit),
                chargingCanBePausedOnDemand: true
            ) == false
        )
    }

    @Test func withheldBeforeTheFirstModeIsKnown() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.initial),
                chargingCanBePausedOnDemand: true
            ) == false
        )
    }
}
