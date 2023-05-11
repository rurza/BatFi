//
//  ChargingManager.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import AsyncAlgorithms
import Clients
//import ClientsLive
import Defaults
import Dependencies
import Foundation
import IOKit.pwr_mgt
import os
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

    public init() { }

    public func appWillQuit() {
        logger.debug("App will quit")
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            try? await helperClient.turnOnAutoChargingMode()
            try? await helperClient.quitChargingHelper()
            semaphore.signal()
        }
        semaphore.wait()
        logger.debug("I tried to turn on charging and quit the helper.")
    }

    public func setUpObserving() {
        Task {
            await fetchChargingState(withHelperQuitting: false)
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
            for await sleepNote in sleepClient.observeMacSleepStatus() {
                switch sleepNote {
                case .willSleep:
                    if let state, state.mode == .forceDischarge {
                        await inhibitChargingIfNeeded(with: state)
                        self.state = nil
                    }
                case .didWake:
                    break
                }

            }
        }

        Task {
            for await _ in screenParametersClient.screenDidChangeParameters().debounce(for: .seconds(2)) {
                await fetchChargingState(withHelperQuitting: false)
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
        let logger = Logger(category: "♟️ TASK \( UUID())")
        logger.debug("Started working on a task.")
        guard manageCharging else {
            try? await helperClient.turnOnAutoChargingMode()
            return
        }
        guard let state else {
            logger.warning("No charging state state")
            await fetchChargingState(withHelperQuitting: false)
            return
        }
        do {
            let currentBatteryLevel = powerState.batteryLevel
            if currentBatteryLevel >= (chargeLimit - 1) {
                if currentBatteryLevel > chargeLimit && allowDischarging && state.lidOpened {
                    await turnOnForceDischargeIfNeeded(with: state)
                } else {
                    await inhibitChargingIfNeeded(with: state)
                }
                restoreSleepifNeeded()
            } else {
                await turnOnChargingIfNeeded(with: state, preventSleeping: preventSleeping)
            }
        }
    }

    private func turnOnForceDischargeIfNeeded(with state: State) async {
        logger.debug("Should turn on force discharging...")
        if state.mode != .forceDischarge {
            logger.debug("Turning on force discharging")
            do {
                try await helperClient.forceDischarge()
                self.state?.mode = .forceDischarge
                logger.debug("Force discharging TURNED ON")
            } catch {
                logger.critical("Failed to turn on force discharge. Error: \(error)")
            }
        } else {
            logger.debug("Force discharging already turned on")
        }
    }

    private func turnOnChargingIfNeeded(with state: State, preventSleeping: Bool) async {
        logger.debug("Should turn on charging...")
        if state.mode != .charging {
            logger.debug("Turning on charging")
            do {
                try await helperClient.turnOnAutoChargingMode()
                self.state?.mode = .charging
                logger.debug("Charging TURNED ON")
            } catch {
                logger.critical("Failed to turn on charging. Error: \(error)")
            }
            if preventSleeping {
                delaySleep()
            }
        } else {
            logger.debug("Charging already turned on.")
        }
    }

    private func inhibitChargingIfNeeded(with state: State) async {
        logger.debug("Should inhibit charging...")
        if state.mode != .inhibit {
            logger.debug("Inhibiting charging")
            do {
                try await helperClient.inhibitCharging()
                self.state?.mode = .inhibit
                logger.debug("Inhibit Charging TURNED ON")
            } catch {
                logger.critical("Failed to turn on inhibit charging. Error: \(error)")
            }
        } else {
            logger.debug("Inhibit charging already turned on.")
        }
    }

    private func delaySleep() {
        guard sleepAssertion == nil else { return }
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

    private func fetchChargingState(withHelperQuitting helperShouldQuit: Bool) async {
        do {
            logger.debug("Fetching charging status")
            let chargingStatus = try await helperClient.chargingStatus()
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
            logger.error("Error fetching charging state: \(error)")
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
