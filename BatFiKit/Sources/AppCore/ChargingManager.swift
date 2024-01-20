//
//  ChargingManager.swift
//
//
//  Created by Adam on 04/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import IOKit.pwr_mgt
import os
import Settings
import Shared

public final class ChargingManager {
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.sleepAssertionClient) private var sleepAssertionClient
    @Dependency(\.defaults) private var defaults

    private var computerIsAsleep = false
    private lazy var logger = Logger(category: "🔌👨‍💼")

    public init() {}

    public func setUpObserving() {
        Task {
            for await (
                (powerState, inhibitOnSleep, enableSystemChargeLimitOnSleep),
                (preventSleeping, forceCharging, temperature),
                (chargeLimit, manageCharging, allowDischarging)
            ) in combineLatest(
                combineLatest(
                    powerSourceClient.powerSourceChanges(),
                    defaults.observe(.turnOnInhibitingChargingWhenGoingToSleep),
                    defaults.observe(.turnOnSystemChargeLimitingWhenGoingToSleep)
                ),
                combineLatest(
                    defaults.observe(.disableSleep),
                    defaults.observe(.forceCharge),
                    defaults.observe(.temperatureSwitch)
                ),
                combineLatest(
                    defaults.observe(.chargeLimit),
                    defaults.observe(.manageCharging),
                    defaults.observe(.allowDischargingFullBattery)
                )
            ).debounce(for: .seconds(1), clock: AnyClock(self.clock)) {
                logger.debug("✨✨✨✨✨✨✨✨✨✨✨")
                await updateStatus(
                    powerState: powerState,
                    chargeLimit: chargeLimit,
                    manageCharging: manageCharging,
                    allowDischarging: allowDischarging,
                    preventSleeping: preventSleeping,
                    forceCharging: forceCharging,
                    turnOffChargingWithHotBattery: temperature,
                    inhibitChargingOnSleep: inhibitOnSleep,
                    enableSystemChargeLimitOnSleep: enableSystemChargeLimitOnSleep
                )
            }
            logger.warning("The main loop did quit")
        }

        Task {
            for await sleepNote in sleepClient.observeMacSleepStatus() {
                guard defaults.value(.manageCharging) else { continue }
                switch sleepNote {
                case .willSleep:
                    computerIsAsleep = true
                    logger.debug("Mac is going to sleep")
                    let currentMode = await appChargingState.chargingStateMode()
                    if currentMode == .forceDischarge {
                        logger.debug("I will inhibit charging, current mode is force discharge")
                        await inhibitCharging(chargerConnected: false)
                    } else if defaults.value(.turnOnInhibitingChargingWhenGoingToSleep) &&
                        !defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep) &&
                        !defaults.value(.forceCharge)
                    {
                        logger.debug("I will inhibit charging, because user chose the option")
                        await inhibitCharging(chargerConnected: true)
                    } else if defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep) &&
                        !defaults.value(.turnOnInhibitingChargingWhenGoingToSleep) &&
                        !defaults.value(.forceCharge)
                    {
                        logger.debug("I will enable system charge limit, because user chose the option")
                        try? await chargingClient.enableSystemChargeLimit()
                    }
                case .didWake:
                    computerIsAsleep = false
                    try? await fetchAndUpdateAppChargingState()
                    await updateStatusWithCurrentState()
                }
            }
        }

        Task {
            for await _ in screenParametersClient.screenDidChangeParameters() {
                guard defaults.value(.manageCharging) else { continue }
                try? await fetchAndUpdateAppChargingState()
                await updateStatusWithCurrentState()
            }
        }
    }

    public func appWillQuit() async {
        try? await chargingClient.resetChargingMode()
    }

    public func chargeToFull() {
        defaults.setValue(.forceCharge, value: true)
    }

    public func turnOffChargeToFull() {
        defaults.setValue(.forceCharge, value: false)
    }

    private func updateStatusWithCurrentState() async {
        let powerState = try? await powerSourceClient.currentPowerSourceState()
        if let powerState {
            let chargeLimit = defaults.value(.chargeLimit)
            let manageCharging = defaults.value(.manageCharging)
            let allowDischargingFullBattery = defaults.value(.allowDischargingFullBattery)
            let preventSleeping = defaults.value(.disableSleep)
            let forceCharging = defaults.value(.forceCharge)
            let batteryTemperature = defaults.value(.temperatureSwitch)
            let inhibitChargingOnSleep = defaults.value(.turnOnInhibitingChargingWhenGoingToSleep)
            let enableSystemChargeLimitOnSleep = defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep)
            await updateStatus(
                powerState: powerState,
                chargeLimit: Int(chargeLimit),
                manageCharging: manageCharging,
                allowDischarging: allowDischargingFullBattery,
                preventSleeping: preventSleeping,
                forceCharging: forceCharging,
                turnOffChargingWithHotBattery: batteryTemperature,
                inhibitChargingOnSleep: inhibitChargingOnSleep,
                enableSystemChargeLimitOnSleep: enableSystemChargeLimitOnSleep
            )
        }
    }

    @MainActor
    func updateStatus(
        powerState: PowerState,
        chargeLimit: Int,
        manageCharging: Bool,
        allowDischarging: Bool,
        preventSleeping: Bool,
        forceCharging: Bool,
        turnOffChargingWithHotBattery: Bool,
        inhibitChargingOnSleep: Bool,
        enableSystemChargeLimitOnSleep: Bool
    ) async {
        logger.debug("⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇⬇")
        defer {
            logger.debug("⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆⬆")
        }
        logger.debug("Battery level: \(powerState.batteryLevel)")
        if powerState.batteryLevel == 100 {
            turnOffChargeToFull()
        }
        guard manageCharging, !forceCharging else {
            logger.debug("Manage charging is turned off or Force charge is turned on")
            await turnOnCharging(
                preventSleeping: false,
                chargerConnected: powerState.chargerConnected,
                manageCharging: manageCharging,
                forceCharge: forceCharging
            )
            return
        }
        if turnOffChargingWithHotBattery, powerState.batteryTemperature > 35 {
            await inhibitCharging(chargerConnected: powerState.chargerConnected)
            return
        }
        guard let lidOpened = await appChargingState.lidOpened() else {
            logger.warning("We don't know if the lid is opened")
            do {
                try await fetchAndUpdateAppChargingState()
                await updateStatus(
                    powerState: powerState,
                    chargeLimit: chargeLimit,
                    manageCharging: manageCharging,
                    allowDischarging: allowDischarging,
                    preventSleeping: preventSleeping,
                    forceCharging: forceCharging,
                    turnOffChargingWithHotBattery: turnOffChargingWithHotBattery,
                    inhibitChargingOnSleep: inhibitChargingOnSleep,
                    enableSystemChargeLimitOnSleep: enableSystemChargeLimitOnSleep
                )
            } catch {
                // ignore the error
            }
            return
        }
        logger.debug("Lid opened: \(lidOpened)")
        do {
            let currentBatteryLevel = powerState.batteryLevel
            if currentBatteryLevel >= chargeLimit {
                if currentBatteryLevel > chargeLimit, allowDischarging, lidOpened, !computerIsAsleep {
                    await turnOnForceDischargeIfNeeded(chargerConnected: powerState.chargerConnected)
                } else if enableSystemChargeLimitOnSleep, !inhibitChargingOnSleep, computerIsAsleep, !forceCharging {
                    try? await chargingClient.enableSystemChargeLimit()
                } else {
                    await inhibitCharging(chargerConnected: powerState.chargerConnected)
                }
                restoreSleepifNeeded()
            } else if inhibitChargingOnSleep, !enableSystemChargeLimitOnSleep, computerIsAsleep, !forceCharging {
                await inhibitCharging(chargerConnected: powerState.chargerConnected)
            } else if enableSystemChargeLimitOnSleep, !inhibitChargingOnSleep, computerIsAsleep, !forceCharging {
                try? await chargingClient.enableSystemChargeLimit()
            } else {
                await turnOnCharging(
                    preventSleeping: preventSleeping,
                    chargerConnected: powerState.chargerConnected,
                    manageCharging: manageCharging,
                    forceCharge: forceCharging
                )
            }
        }
    }

    private func turnOnForceDischargeIfNeeded(chargerConnected: Bool) async {
        let mode = await appChargingState.chargingStateMode()
        logger.debug("Should turn on force discharging...")
        if mode != .forceDischarge {
            if chargerConnected {
                logger.debug("Turning on force discharging")
                do {
                    try await chargingClient.forceDischarge()
                    await appChargingState.updateChargingStateMode(.forceDischarge)
                    logger.debug("Force discharging TURNED ON")
                } catch {
                    logger.critical("Failed to turn on force discharge. Error: \(error)")
                }
            } else {
                await appChargingState.updateChargingStateMode(.chargerNotConnected)
            }
        } else {
            logger.debug("Force discharging already turned on ")
        }
    }

    private func turnOnCharging(
        preventSleeping: Bool,
        chargerConnected: Bool,
        manageCharging: Bool,
        forceCharge: Bool
    ) async {
        logger.debug("Turning on charging")
        do {
            try await chargingClient.turnOnAutoChargingMode()
            if chargerConnected {
                if forceCharge {
                    await appChargingState.updateChargingStateMode(.forceCharge)
                } else {
                    await appChargingState.updateChargingStateMode(.charging)
                }
            } else {
                await appChargingState.updateChargingStateMode(.chargerNotConnected)
            }
            logger.debug("Charging TURNED ON")
        } catch {
            logger.critical("Failed to turn on charging. Error: \(error)")
        }
        if preventSleeping, chargerConnected, manageCharging {
            delaySleepIfNeeded()
        }
    }

    private func inhibitCharging(chargerConnected: Bool) async {
        let mode = await appChargingState.chargingStateMode()
        logger.debug("I will inhibit charging...")
        do {
            if chargerConnected || mode == .forceDischarge {
                try await chargingClient.inhibitCharging()
                // fetch the power state to check if the charger is connected
                let powerState = try? await powerSourceClient.currentPowerSourceState()
                if let powerState, powerState.chargerConnected {
                    await appChargingState.updateChargingStateMode(.inhibit)
                    logger.debug("Inhibit Charging TURNED ON")
                    return
                }
            } else {
                logger.debug("Charger not connected, I will turn on auto charging mode")
                try await chargingClient.turnOnAutoChargingMode()
                await appChargingState.updateChargingStateMode(.chargerNotConnected)
            }

        } catch {
            logger.critical("Failed to turn on inhibit charging. Error: \(error)")
        }
    }

    private func delaySleepIfNeeded() {
        sleepAssertionClient.preventSleepIfNeeded(true)
    }

    private func restoreSleepifNeeded() {
        sleepAssertionClient.preventSleepIfNeeded(false)
    }

    private func fetchAndUpdateAppChargingState() async throws {
        do {
            logger.debug("Fetching charging status")
            let powerState = try await powerSourceClient.currentPowerSourceState()
            let chargingStatus = try await chargingClient.chargingStatus()
            let forceChargeSettings = defaults.value(.forceCharge)
            logger.debug("Current status: \(chargingStatus.description, privacy: .public)")
            if chargingStatus.forceDischarging {
                await appChargingState.updateChargingStateMode(.forceDischarge)
            } else {
                if powerState.chargerConnected {
                    logger.debug("Charger is connected")
                    if chargingStatus.inhitbitCharging {
                        await appChargingState.updateChargingStateMode(.inhibit)
                    } else if forceChargeSettings {
                        await appChargingState.updateChargingStateMode(.forceCharge)
                    } else {
                        await appChargingState.updateChargingStateMode(.charging)
                    }
                } else {
                    logger.debug("Charger is NOT connected")
                    await appChargingState.updateChargingStateMode(.chargerNotConnected)
                }
            }
            await appChargingState.updateLidOpenedStatus(!chargingStatus.lidClosed)
        } catch {
            logger.error("Error fetching charging state: \(error)")
            throw error
        }
    }
}
