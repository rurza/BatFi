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

public final class ChargingManager {
    @Dependency(\.helperClient)             private var helperClient
    @Dependency(\.powerSourceClient)        private var powerSourceClient
    @Dependency(\.screenParametersClient)   private var screenParametersClient
    @Dependency(\.sleepClient)              private var sleepClient
    @Dependency(\.defaultsClient)           private var defaultsClient
    @Dependency(\.suspendingClock)          private var clock

    private var sleepAssertion: IOPMAssertionID?
    private lazy var logger = Logger(category: "🔌👨‍💼")
    var state: State?

    public init() {
        setUpObserving()
    }

    private func setUpObserving() {

        Task {
            await fetchState()
            for await ((powerState, preventSleeping), (chargeLimit, manageCharging, allowDischarging)) in combineLatest(
                combineLatest(
                    powerSourceClient.powerSourceChanges(),
                    defaultsClient.observePreventSleeping()
                ),
                combineLatest(
                    defaultsClient.observeChargeLimit(),
                    defaultsClient.observeManageCharging(),
                    defaultsClient.observeAllowDischargingFullBattery()
                )
            ).debounce(for: .seconds(1)) {
                logger.debug("something changed")
                await updateStatus(
                    manageCharging: manageCharging,
                    chargeLimit: chargeLimit,
                    allowDischarging: allowDischarging,
                    preventSleeping: preventSleeping,
                    powerState: powerState
                )
            }
            logger.warning("The main loop did quit")
        }

        Task {
            for await _ in sleepClient.macDidWake() {
                await fetchState()
                await updateStatusWithCurrentState()
            }
        }

        Task {
            for await _ in screenParametersClient.screenDidChangeParameters() {
                await fetchState()
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
            let preventSleeping = Defaults[.disableSleep]
            await updateStatus(
                manageCharging: manageCharging,
                chargeLimit: Int(chargeLimit),
                allowDischarging: allowDischargingFullBattery,
                preventSleeping: preventSleeping,
                powerState: powerState
            )
        }
    }

    @MainActor
    private func updateStatus(
        manageCharging: Bool,
        chargeLimit: Int,
        allowDischarging: Bool,
        preventSleeping: Bool,
        powerState: PowerState
    ) async {
        let taskId = UUID()
        let logger = Logger(category: "♟️ TASK \(taskId)")
        logger.debug("Started working on a task.")
        guard manageCharging else {
            try? await helperClient.turnOnAutoChargingMode(true)
            return
        }
        guard let state else {
            await fetchState()
            return
        }
        do {
            let currentBatteryLevel = powerState.batteryLevel
            if currentBatteryLevel >= (chargeLimit - 1) {
                if currentBatteryLevel > chargeLimit && allowDischarging && state.lidOpened {
                    logger.debug("Force discharging")
                    do {
                        try await helperClient.forceDischarge(true)
                    } catch {
                        logger.critical("Failed to turn on force discharge. Error: \(error)")
                    }
                } else {
                    logger.debug("Inhibiting charging")
                    do {
                        try await helperClient.inhibitCharging(true)
                    } catch {
                        logger.critical("Failed to turn on inhibit charging. Error: \(error)")
                    }
                }
                restoreSleepifNeeded()
            } else {
                logger.debug("Turning on charging")
                do {
                    try await helperClient.turnOnAutoChargingMode(true)
                } catch {
                    logger.critical("Failed to turn on charging. Error: \(error)")
                }
                if preventSleeping {
                    delaySleep()
                }
            }
        }
        logger.debug("DONE")
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

    private func restoreSleepifNeeded() {
        if let sleepAssertion {
            logger.debug("Returning sleep")
            IOPMAssertionRelease(sleepAssertion)
            self.sleepAssertion = nil
        }
    }

    private func fetchState() async {
        do {
            let chargingStatus = try await helperClient.chargingStatus(true)
            let mode: State.Mode
            if chargingStatus.forceDischarging {
                mode = .forceDischarge
            } else if chargingStatus.inhitbitCharging {
                mode = .inhibit
            } else {
                mode = .charging
            }
            self.state = State(mode: mode, lidOpened: !chargingStatus.lidClosed)
        } catch {
            logger.debug("Can not fetch state")
        }
    }
}

extension ChargingManager {
    struct State {
        enum Mode {
            case charging
            case inhibit
            case forceDischarge
        }
        var mode: Mode
        var lidOpened:Bool
    }
}
