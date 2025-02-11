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

public actor ChargingManager: ChargingModeManager {
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.sleepAssertionClient) private var sleepAssertionClient
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.analyticsClient) private var analytics
    @Dependency(\.date) private var date

    private var computerIsAsleep = false
    private lazy var logger = Logger(category: "Charging Manager")

    private var powerStatePullingTask: Task<Void, Never>?

    private var lastChargerConnectedStatus: ChargerConnectedStatus?

    public init() {}

    public func setUpObserving() {
        Task {
            for await (
                (
                    (userTempChargingMode, powerState)
                ),
                (
                    (inhibitOnSleep, enableSystemChargeLimitOnSleep, disableSleepDuringDischarge),
                    (preventAutomaticSleep, temperature),
                    (chargeLimit, manageCharging, allowDischarging)
                )
            ) in combineLatest(
                combineLatest(
                    appChargingState.userTempOverrideDidChange(),
                    powerSourceClient.powerSourceChanges()
                ),
                combineLatest(
                    combineLatest(
                        defaults.observe(.turnOnInhibitingChargingWhenGoingToSleep),
                        defaults.observe(.turnOnSystemChargeLimitingWhenGoingToSleep),
                        defaults.observe(.disableSleepDuringDischarging)
                    ),
                    combineLatest(
                        defaults.observe(.disableSleep),
                        defaults.observe(.temperatureSwitch)
                    ),
                    combineLatest(
                        defaults.observe(.chargeLimit),
                        defaults.observe(.manageCharging),
                        defaults.observe(.allowDischargingFullBattery)
                    )
                )
            ).debounce(for: .milliseconds(100), clock: AnyClock(self.clock)) {
                await updateStatus(
                    powerState: powerState,
                    userTempChargingMode: userTempChargingMode,
                    chargeLimit: chargeLimit,
                    manageCharging: manageCharging,
                    allowDischarging: allowDischarging,
                    preventAutomaticSleep: preventAutomaticSleep,
                    turnOffChargingWithHotBattery: temperature,
                    inhibitChargingOnSleep: inhibitOnSleep,
                    enableSystemChargeLimitOnSleep: enableSystemChargeLimitOnSleep,
                    disableSleepDuringDischarge: disableSleepDuringDischarge
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
                    let appChargingMode = await appChargingState.currentAppChargingMode()
                    let currentMode = appChargingMode.mode
                    let powerState = try? await powerSourceClient.currentPowerSourceState()
                    let currentLimit = appChargingMode.userTempOverride?.limit ?? defaults.value(.chargeLimit)
                    let tempOverride = appChargingMode.userTempOverride != nil
                    let inhibitOnSleep = defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep)
                    let systemChargingLimitOnSleep = defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep)

                    if powerState?.batteryLevel ?? 0 < currentLimit,
                        (inhibitOnSleep && !systemChargingLimitOnSleep), !tempOverride {
                        logger.notice("current mode: \(appChargingMode), turn inhibit on sleep: \(inhibitOnSleep)")
                        await inhibitCharging(chargerConnected: true, currentMode: currentMode)
                    } else if systemChargingLimitOnSleep, !inhibitOnSleep, !tempOverride {
                        logger.notice("current mode: \(appChargingMode), enable system charging limit on sleep")
                        logger.notice("I will enable system charge limit, because user chose the option and there is no temp override")
                        try? await chargingClient.enableSystemChargeLimit()
                    }
                case .didWake:
                    logger.notice("Mac did wake up")
                    computerIsAsleep = false
                    await fetchAndUpdateAppChargingState()
                    await updateStatusWithCurrentState()
                }
            }
        }

        Task {
            for await _ in screenParametersClient.screenDidChangeParameters() {
                guard defaults.value(.manageCharging) else { continue }
                await fetchAndUpdateAppChargingState()
                await updateStatusWithCurrentState()
            }
        }
    }

    public func appWillQuit() async {
        try? await chargingClient.turnOnAutoChargingMode()
        await restoreSleepifNeeded()
    }

    nonisolated 
    public func forceCharge() {
        Task {
            await appChargingState.setTempOverride(.init(limit: 100))
        }
    }

    nonisolated public func stopForceCharge() {
        removeTempOverride()
    }

    nonisolated public func dischargeBattery() {
        dischargeBattery(to: 0)
    }

    nonisolated public func inhibitCharging() {
        Task {
            let powerState = try await powerSourceClient.currentPowerSourceState()
            await appChargingState.setTempOverride(.init(limit: powerState.batteryLevel))
        }
    }

    nonisolated public func dischargeBattery(to limit: Int) {
        guard limit >= 0, limit <= 100 else { return }
        Task {
            await appChargingState.setTempOverride(.init(limit: limit))
        }
    }

    nonisolated public func stopDischargingBattery() {
        removeTempOverride()
    }

    nonisolated public func stopOverride() {
        removeTempOverride()
    }

    nonisolated private func removeTempOverride() {
        Task {
            await appChargingState.setTempOverride(nil)
        }
    }

    private func startPullingPowerStateIfNeeded() async {
        guard powerStatePullingTask == nil else { return }
        powerStatePullingTask = Task { [weak self] in
            guard let self else { return }
            await analytics.addBreadcrumb(category: .chargingManager, message: "started pulling power state")
            while !Task.isCancelled {
                #if DEBUG
                try? await clock.sleep(for: .seconds(3))
                #else
                try? await clock.sleep(for: .seconds(30))
                #endif
                await updateStatusWithCurrentState()
            }
        }
    }

    private func cancelPullingPowerStateTaskIfNeeded() async {
        guard powerStatePullingTask != nil else { return }
        await analytics.addBreadcrumb(category: .chargingManager, message: "pulling power state stopped")
        powerStatePullingTask?.cancel()
        powerStatePullingTask = nil
    }

    private func updateStatusWithCurrentState() async {
        let powerState = try? await powerSourceClient.currentPowerSourceState()
        let userTempChargingMode = await appChargingState.currentUserTempOverrideMode()
        logger.debug("\(#function). Battery level: \(powerState?.batteryLevel.description ?? "no power state"), Charge limit: \(self.defaults.value(.chargeLimit))")
        if let powerState {
            let chargeLimit = defaults.value(.chargeLimit)
            let manageCharging = defaults.value(.manageCharging)
            let allowDischargingFullBattery = defaults.value(.allowDischargingFullBattery)
            let preventAutomaticSleep = defaults.value(.disableSleep)
            let batteryTemperature = defaults.value(.temperatureSwitch)
            let inhibitChargingOnSleep = defaults.value(.turnOnInhibitingChargingWhenGoingToSleep)
            let enableSystemChargeLimitOnSleep = defaults.value(.turnOnSystemChargeLimitingWhenGoingToSleep)
            let disableSleepDuringDischarge = defaults.value(.disableSleepDuringDischarging)

            await updateStatus(
                powerState: powerState,
                userTempChargingMode: userTempChargingMode,
                chargeLimit: Int(chargeLimit),
                manageCharging: manageCharging,
                allowDischarging: allowDischargingFullBattery,
                preventAutomaticSleep: preventAutomaticSleep,
                turnOffChargingWithHotBattery: batteryTemperature,
                inhibitChargingOnSleep: inhibitChargingOnSleep,
                enableSystemChargeLimitOnSleep: enableSystemChargeLimitOnSleep,
                disableSleepDuringDischarge: disableSleepDuringDischarge
            )
        }
    }

    private func updateStatus(
        powerState: PowerState,
        userTempChargingMode: UserTempChargingMode?,
        chargeLimit: Int,
        manageCharging: Bool,
        allowDischarging: Bool,
        preventAutomaticSleep: Bool,
        turnOffChargingWithHotBattery: Bool,
        inhibitChargingOnSleep: Bool,
        enableSystemChargeLimitOnSleep: Bool,
        disableSleepDuringDischarge: Bool
    ) async {
        let chargerConnected = powerState.chargerConnected
        let previousChargerConnectedState = self.lastChargerConnectedStatus
        updateLastChargerConnectedStateIfNeeded(chargerConnected)
        let appChargingMode = await appChargingState.currentAppChargingMode()
        let currentMode = appChargingMode.mode

        guard currentMode != .initial else {
            logger.debug("We don't have a mode yet")
            await analytics.addBreadcrumb(category: .chargingManager, message: "App mode is still set to initial")
            await fetchAndUpdateAppChargingState()
            return
        }

        await setUpDelaySleep(
            preventAutomaticSleep &&
            powerState.batteryLevel < userTempChargingMode?.limit ?? chargeLimit &&
            powerState.chargerConnected
        )

        guard manageCharging else {
            logger.debug("Manage charging is turned off")
            await turnOnCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            return
        }
        
        if turnOffChargingWithHotBattery, powerState.batteryTemperature > Constant.batteryTemperatureWarning {
            logger.notice("Battery is hot")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Battery is hot, \(powerState.batteryTemperature)")
            await inhibitCharging(chargerConnected: chargerConnected, currentMode: currentMode)
            return
        }

        let isLidOpened: Bool
        if let lidOpened = await appChargingState.lidOpened() {
            isLidOpened = lidOpened
        } else {
            isLidOpened = await fetchLidStatus()
        }

        let isLidOpenedOrSleepDisabled = isLidOpened || disableSleepDuringDischarge

        let currentBatteryLevel = powerState.batteryLevel
        if let tempLimit = userTempChargingMode?.limit {
            logger.debug("User set temp limit to \(tempLimit)")
            if currentBatteryLevel > tempLimit, isLidOpenedOrSleepDisabled {
                return await turnOnDischarging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            } else if currentBatteryLevel < tempLimit {
                removeTempOverrideIfStatusHasChanged(previousStatus: previousChargerConnectedState)
                return await turnOnCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            } else {
                return await inhibitCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            }
        } else {
            if currentBatteryLevel >= chargeLimit {
                if currentBatteryLevel > chargeLimit, allowDischarging, isLidOpenedOrSleepDisabled, !computerIsAsleep {
                    await turnOnDischarging(
                        chargerConnected: chargerConnected,
                        currentMode: currentMode
                    )
                    return
                } else if enableSystemChargeLimitOnSleep, !inhibitChargingOnSleep, computerIsAsleep {
                    await turnOnSystemChargingLimit()
                    return
                } else {
                    await inhibitCharging(
                        chargerConnected: chargerConnected,
                        currentMode: currentMode
                    )
                    return
                }
            } else if inhibitChargingOnSleep, !enableSystemChargeLimitOnSleep, computerIsAsleep {
                return await inhibitCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            } else if enableSystemChargeLimitOnSleep, !inhibitChargingOnSleep, computerIsAsleep {
                return await turnOnSystemChargingLimit()
            } else {
                return await turnOnCharging(
                    chargerConnected: chargerConnected,
                    currentMode: currentMode
                )
            }
        }
    }

    private func turnOnCharging(chargerConnected: Bool, currentMode: ChargingMode) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        logger.debug("Turning on charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on charging")
        do {
            if defaults.value(.allowDischargingFullBattery) {
                try? await sleepAssertionClient.disableSleep(false)
            }
            try await chargingClient.turnOnAutoChargingMode()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Charging turned on")
            await appChargingState.updateChargingMode(.charging)
        } catch {
            logger.warning("Failed to turn on charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on charging. Error: \(error.localizedDescription)")
        }
    }

    private func inhibitCharging(chargerConnected: Bool, currentMode: ChargingMode) async {
        await updateChargerConnected(chargerConnected)
        logger.debug("Inhibiting charging")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibiting charging")
        do {
            if defaults.value(.allowDischargingFullBattery) {
                try? await sleepAssertionClient.disableSleep(false)
            }
            try await chargingClient.inhibitCharging()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Inhibit charging turned on")
            await appChargingState.updateChargingMode(.inhibit)
            await startPullingPowerStateIfNeeded()
        } catch {
            logger.warning("Failed to inhibit charging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to inhibit charging. Error: \(error.localizedDescription)")
        }
    }

    private func turnOnDischarging(chargerConnected: Bool, currentMode: ChargingMode) async {
        await cancelPullingPowerStateTaskIfNeeded()
        await updateChargerConnected(chargerConnected)
        if defaults.value(.disableSleepDuringDischarging) {
            try? await sleepAssertionClient.disableSleep(true)
        }
        guard chargerConnected else {
            logger.debug("Charger not connected, skipping discharging")
            return
        }
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on discharging")
        logger.debug("Turning on discharging")
        do {
            try await chargingClient.forceDischarge()
            await analytics.addBreadcrumb(category: .chargingManager, message: "Discharging turned on")
            await appChargingState.updateChargingMode(.forceDischarge)

        } catch {
            logger.warning("Failed to turn on discharging: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on discharging. Error: \(error.localizedDescription)")
        }
    }

    private func turnOnSystemChargingLimit() async {
        await cancelPullingPowerStateTaskIfNeeded()
        logger.notice("Turning on system charging limit")
        await analytics.addBreadcrumb(category: .chargingManager, message: "Turning on system charging limit")
        do {
            if defaults.value(.allowDischargingFullBattery) {
                try? await sleepAssertionClient.disableSleep(false)
            }
            try await chargingClient.enableSystemChargeLimit()
            await analytics.addBreadcrumb(category: .chargingManager, message: "System charging limit turned on")
        } catch {
            logger.warning("Failed to turn on system charging limit: \(error, privacy: .public)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Failed to turn on system charging limit. Error: \(error.localizedDescription)")
        }
    }

    private func setUpDelaySleep(_ delay: Bool) async {
        if delay {
            await delaySleepIfNeeded()
        } else {
            await restoreSleepifNeeded()
        }
    }

    private func delaySleepIfNeeded() async {
        if await !sleepAssertionClient.preventsSleep() {
            logger.notice("Preventing sleep")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Preventing sleep")
            await sleepAssertionClient.preventSleepIfNeeded(preventSleep: true)
        }
    }

    private func restoreSleepifNeeded() async {
        if await sleepAssertionClient.preventsSleep() {
            logger.notice("Restoring sleep")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Restoring sleep")
            await sleepAssertionClient.preventSleepIfNeeded(false)
        }
    }

    private func fetchAndUpdateAppChargingState() async {
        do {
            logger.notice("Fetching charging state")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Fetching charging state")
            let powerState = try await powerSourceClient.currentPowerSourceState()
            let chargingStatus = try await chargingClient.chargingStatus()
            let userTempOverride = await appChargingState.currentUserTempOverrideMode()
            logger.notice("Current status: \(chargingStatus.description, privacy: .public)")

            let mode: ChargingMode
            if chargingStatus.forceDischarging {
                mode = .forceDischarge
            } else if chargingStatus.inhitbitCharging {
                mode = .inhibit
            } else if chargingStatus.isCharging {
                mode = .charging
            } else {
                mode = .inhibit
            }

            await appChargingState.updateLidOpenedStatus(!chargingStatus.lidClosed)
            await appChargingState.setAppChargingMode(
                .init(mode: mode, userTempOverride: userTempOverride, chargerConnected: powerState.chargerConnected)
            )
            await updateStatusWithCurrentState()
        } catch {
            logger.error("Error fetching charging state: \(error)")
            await analytics.addBreadcrumb(category: .chargingManager, message: "Error fetching charging state: \(error.localizedDescription)")
        }
    }

    private func fetchLidStatus() async -> Bool {
        logger.notice("We don't know if the lid is opened")
        await analytics.addBreadcrumb(category: .chargingManager, message: "We don't know if the lid is opened")
        do {
            let chargingStatus = try await chargingClient.chargingStatus()
            await appChargingState.updateLidOpenedStatus(!chargingStatus.lidClosed)
            return !chargingStatus.lidClosed
        } catch {
            logger.notice("Failed to fetch lid status: \(error)")
            await analytics.captureError(error: error)
            return false
        }
    }

    private func updateChargerConnected(_ chargerConnected: Bool) async {
        await analytics.addBreadcrumb(category: .chargingManager, message: "Updating charger connected status")
        logger.notice("Updating charger connected status: \(chargerConnected)")
        await appChargingState.setChargerConnected(chargerConnected)
    }

    // MARK: - Last state of charger connected
    private func updateLastChargerConnectedStateIfNeeded(_ chargerConnected: Bool) {
        let newState = ChargerConnectedStatus(date: date.now, isConnected: chargerConnected)
        if let lastChargerConnectedStatus {
            if lastChargerConnectedStatus.isConnected != chargerConnected {
                logger.debug("Update last charger connected status: \(chargerConnected)")
                self.lastChargerConnectedStatus = newState
            }
        } else {
            self.lastChargerConnectedStatus = newState
        }
    }

    private func removeTempOverrideIfStatusHasChanged(previousStatus: ChargerConnectedStatus?) {
        if let lastChargerConnectedStatus, let previousStatus,
           !previousStatus.isConnected, lastChargerConnectedStatus.isConnected,
           previousStatus.date.timeIntervalSince(date.now) < -15 {
            logger.debug("Removing temp override because charger connection status has not changed for a while")
            removeTempOverride()
        }
    }
}
