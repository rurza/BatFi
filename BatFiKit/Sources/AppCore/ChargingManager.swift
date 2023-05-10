//
//  ChargingManager.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import AsyncAlgorithms
import Charging
import Defaults
import Dependencies
import Foundation
import IOKit.pwr_mgt
import os
import PowerSource
import Settings
import Shared

@MainActor
public final class ChargingManager {
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.suspendingClock) private var clock
    private var sleepAssertion: IOPMAssertionID?
    private lazy var logger = Logger(category: "🔌👨‍💼")

    public init() {
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            for await ((powerState), (chargeLimit, manageCharging, allowDischarging)) in combineLatest(
                powerSourceClient.powerSourceChanges(),
                combineLatest(
                    Defaults.updates(.chargeLimit),
                    Defaults.updates(.manageCharging),
                    Defaults.updates(.allowDischargingFullBattery)
                )
            ) {
                logger.debug(
                    """
power source chaned OR charge limit OR "manager charging" OR "allow discharging" CHANGED
"""
                )
                await updateStatus(
                    manageCharging: manageCharging,
                    chargeLimit: Int(chargeLimit),
                    allowDischarging: allowDischarging,
                    powerState: powerState
                )
            }
        }

        Task {
            for await _ in sleepClient.macWillSleep() {

            }
        }

        Task {
            for await _ in sleepClient.macDidWake() {
                await updateStatusWithCurrentState()
            }
        }

        Task {
            for await _ in screenParametersClient.screenDidChangeParameters() {
                await updateStatusWithCurrentState()
            }
        }
    }

    private func updateStatusWithCurrentState() async {
        let powerState = try? powerSourceClient.currentPowerSourceState()
        if let powerState {
            let chargeLimit = Defaults[.chargeLimit]
            let manageCharging = Defaults[.manageCharging]
            let allowDischargingFullBattery = Defaults[.allowDischargingFullBattery]
            await updateStatus(
             manageCharging: manageCharging,
             chargeLimit: Int(chargeLimit),
             allowDischarging: allowDischargingFullBattery,
             powerState: powerState
            )
        }
    }

    private func updateStatus(
        manageCharging: Bool,
        chargeLimit: Int,
        allowDischarging: Bool,
        powerState: PowerState
    ) async {
        logger.debug(#function)
        guard manageCharging else {
            try? await chargingClient.turnOnAutoChargingMode()
            return
        }
        do {
            let chargingStatus = try await chargingClient.chargingStatus()
            let currentBatteryLevel = powerState.batteryLevel
            if currentBatteryLevel >= (chargeLimit - 1) {
                if currentBatteryLevel > chargeLimit && allowDischarging && !chargingStatus.lidClosed {
                    if !chargingStatus.forceDischarging {
                        logger.debug("Force discharging")
                        do {
                            try await chargingClient.forceDischarge()
                        } catch {
                            logger.critical("Failed to turn on force discharge. Error: \(error)")
                        }
                    }
                } else {
                    if !chargingStatus.inhitbitCharging {
                        logger.debug("Inhibiting charging")
                        do {
                            try await chargingClient.inhibitCharging()
                        } catch {
                            logger.critical("Failed to turn on inhibit charging. Error: \(error)")
                        }
                        delaySleep()
                    }
                }
                if let sleepAssertion {
                    IOPMAssertionRelease(sleepAssertion)
                }
            } else {
                if !chargingStatus.isCharging {
                    logger.debug("Turning on charging")
                    do {
                        try await chargingClient.turnOnAutoChargingMode()
                    } catch {
                        logger.critical("Failed to turn on charging. Error: \(error)")
                    }
                }
            }
        } catch {
            logger.error("Failed to get charging status. Error: \(error)")
        }

    }

    private func delaySleep() {
        logger.debug("Delaying sleep")
        var assertionID: IOPMAssertionID = IOPMAssertionID(0)
        let reason: CFString = "BatFi" as NSString
        let cfAssertion: CFString = kIOPMAssertionTypePreventSystemSleep as NSString
        let success = IOPMAssertionCreateWithName(
            cfAssertion,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        if success == kIOReturnSuccess {
            sleepAssertion = assertionID
        }
    }
}
