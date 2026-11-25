//
//  ChargerConnectionTests.swift
//  BatFi
//
//  The derived charger connection is wrong in exactly one situation, and it is the one
//  BatFi creates for itself: force discharge isolates the adapter, so IOPS reports
//  "Battery Power" while the charger is plugged in. On firmware that has dropped
//  `ExternalConnected` that made `turnOnDischarging` stop re-asserting a discharge it was
//  still running, and released the sleep assertion mid-discharge.
//

import Testing

@testable import AppShared

@Suite struct ChargerConnectionTests {
    /// Listed rather than iterated: `ChargingMode` is not `CaseIterable`, and making it so
    /// to serve a test would put a decision about a public type in the wrong place.
    private let allModes: [ChargingMode] = [.initial, .charging, .inhibit, .forceDischarge]

    /// The failing case. Derived, reads disconnected, and BatFi is force-discharging —
    /// which is *why* it reads disconnected.
    @Test func aDerivedDisconnectionIsNotBelievedWhileForceDischarging() {
        #expect(
            ChargerConnection.isConnected(reported: false, isDerived: true, appMode: .forceDischarge)
        )
    }

    /// Only in that mode. A derived "battery power" in any other mode really does mean the
    /// charger came out, and refusing to believe it would pin BatFi to a charger that is
    /// not there.
    @Test func aDerivedDisconnectionIsBelievedInEveryOtherMode() {
        for mode in allModes where mode != .forceDischarge {
            #expect(
                !ChargerConnection.isConnected(reported: false, isDerived: true, appMode: mode),
                "\(mode.rawValue)"
            )
        }
    }

    /// A value that came from `ExternalConnected` is never second-guessed, in any mode.
    /// That key is precise about this exact case, which is the whole reason it is preferred.
    @Test func aReportedDisconnectionIsAlwaysBelieved() {
        for mode in allModes {
            #expect(
                !ChargerConnection.isConnected(reported: false, isDerived: false, appMode: mode),
                "\(mode.rawValue)"
            )
        }
    }

    @Test func aConnectedChargerIsConnectedHoweverItWasLearned() {
        for mode in allModes {
            #expect(ChargerConnection.isConnected(reported: true, isDerived: true, appMode: mode))
            #expect(ChargerConnection.isConnected(reported: true, isDerived: false, appMode: mode))
        }
    }

    // MARK: - On battery

    @Test func aReportedDisconnectionIsOnBattery() {
        #expect(ChargerConnection.isOnBattery(reported: false, isDerived: false, appMode: .charging))
    }

    @Test func aConnectedChargerIsNeverOnBattery() {
        for mode in allModes {
            #expect(!ChargerConnection.isOnBattery(reported: true, isDerived: true, appMode: mode))
            #expect(!ChargerConnection.isOnBattery(reported: true, isDerived: false, appMode: mode))
        }
    }

    /// BatFi's own force discharge isolates the adapter, so derived firmware reads "Battery
    /// Power" while the charger is still in. That is not being on battery.
    @Test func batFisOwnForceDischargeIsNotOnBattery() {
        #expect(!ChargerConnection.isOnBattery(reported: false, isDerived: true, appMode: .forceDischarge))
    }

    /// On firmware without `ExternalConnected`, a derived "Battery Power" while BatFi charges
    /// or holds the charge is the charger having come out: that is being on battery. Only
    /// BatFi's own force discharge explains it away.
    @Test(arguments: [ChargingMode.charging, .inhibit])
    func aDerivedDisconnectionWhileChargingOrHoldingIsOnBattery(mode: ChargingMode) {
        #expect(ChargerConnection.isOnBattery(reported: false, isDerived: true, appMode: mode))
    }

    /// The charger really coming out mid-discharge still counts: a reported disconnection is
    /// believed in every mode, force discharge included.
    @Test func aReportedDisconnectionDuringForceDischargeIsOnBattery() {
        #expect(ChargerConnection.isOnBattery(reported: false, isDerived: false, appMode: .forceDischarge))
    }
}
