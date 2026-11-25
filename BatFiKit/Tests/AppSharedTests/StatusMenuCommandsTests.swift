//
//  StatusMenuCommandsTests.swift
//  BatFi
//
//  Which commands the status menu may offer. The rule that matters here is the backend gate:
//  "Inhibit Charging" is offered wherever the Mac can hold charge at its current level — by
//  its own inhibit, or by freezing Apple's charge limit — and nowhere else, because there it
//  is a button that reports success and changes nothing the user asked to change.
//

import Foundation
import Shared
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

    // MARK: - Macs that can hold charge at the current level

    /// MPX-41: the command came back on macOS 27 firmware, held by Apple's own limit.
    @Test func offeredWhileChargingUnderTheSystemChargeLimit() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                backend: .systemChargeLimit
            )
        )
    }

    @Test func offeredWhileForceDischargingUnderTheSystemChargeLimit() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.forceDischarge),
                backend: .systemChargeLimit
            )
        )
    }

    /// Fail-open while the backend is unknown, as the menu always has been.
    @Test func offeredWhileTheBackendIsUnknown() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                backend: nil
            )
        )
    }

    @Test func offeredWhileChargingOnAMacThatCanPause() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                backend: .chte
            )
        )
    }

    @Test func offeredWhileForceDischargingOnAMacThatCanPause() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.forceDischarge),
                backend: .chte
            )
        )
    }

    // MARK: - Macs that cannot hold charge where it is

    /// "Run on Battery" is engaged, so the menu would offer "Inhibit Charging" beside it — on
    /// firmware whose band lets the battery fall five points and charges it back.
    @Test func withheldWhileForceDischargingUnderTheFirmwareRange() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.forceDischarge),
                backend: .firmwareRange
            ) == false
        )
    }

    @Test func withheldWhileChargingUnderTheFirmwareRange() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                backend: .firmwareRange
            ) == false
        )
    }

    @Test func withheldWhereNothingIsSupported() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging),
                backend: .unsupported
            ) == false
        )
    }

    // MARK: - Rules that predate the backend gate

    @Test func withheldWhileTheChargerIsOut() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.charging, chargerConnected: false),
                backend: .chte
            ) == false
        )
    }

    @Test func withheldWhileAlreadyInhibiting() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.inhibit),
                backend: .chte
            ) == false
        )
    }

    @Test func withheldBeforeTheFirstModeIsKnown() {
        #expect(
            StatusMenuCommands.showsInhibitCharging(
                mode: mode(.initial),
                backend: .chte
            ) == false
        )
    }
}
