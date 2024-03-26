//
//  ChargingFeature.swift
//
//
//  Created by Adam Różyński on 26/03/2024.
//

import AppShared
import Clients
import ComposableArchitecture
import Foundation

@Reducer
struct ChargingFeature {
    @ObservableState
    struct State: Equatable {
        @Shared
        var currentChargingMode: AppChargingMode

        @Shared
        var lidOpened: Bool

        var computerIsAsleep = false

        var powerState: PowerState?

        // Preferences
        @Shared
        var manageCharging: Bool
        @Shared
        var disableSleep: Bool
        @Shared
        var temperatureSwitch: Bool
        @Shared
        var allowDischarging: Bool
        @Shared
        var enableSystemChargeLimitOnSleep: Bool
        @Shared
        var chargeLimit: Int
        @Shared
        var inhibitChargingOnSleep: Bool
    }

    enum Action: Equatable {
        case appWillQuit
        case settingsDidChange
        case task
        case updateComputerIsAsleep(Bool)
        case updatePowerState(PowerState)
        case updateCurrentChargingMode(AppChargingMode)
        case updateLidIsOpened(Bool)
    }

    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient
    @Dependency(\.sleepAssertionClient) private var sleepAssertionClient
    @Dependency(\.sleepClient) private var sleepClient


    var body: some ReducerOf<ChargingFeature> {
        Reduce { state, action in
            guard state.manageCharging else {
                return .run { _ in
                    try await chargingClient.turnOnAutoChargingMode()
                }
            }
            let disableSleep = state.disableSleep
            switch action {
            case .task:
                return .run { send in
                    let status = try await chargingClient.chargingStatus()
                    await send(.updateLidIsOpened(!status.lidClosed))
                    Task {
                        for await powerState in await powerSourceClient.powerSourceChanges() {
                            await send(.updatePowerState(powerState))
                        }
                    }
                    Task {
                        for await sleepNote in await sleepClient.observeMacSleepStatus() {
                            switch sleepNote {
                            case .willSleep:
                                // TODO
                                break
                            case .didWake:
                                // TODO
                                break
                            }
                        }
                    }
                    Task {
                        for await _ in await screenParametersClient.screenDidChangeParameters() {

                        }
                    }

                }

            case let .updateLidIsOpened(lidIsOpened):
                state.lidOpened = lidIsOpened
                return .none
            case let .updateCurrentChargingMode(mode):
                state.currentChargingMode = mode
                return .none
            case let .updateComputerIsAsleep(isAsleep):
                state.computerIsAsleep = isAsleep
                return .none
            case .settingsDidChange:
                return changeModeIfNeeded(state: state)
            case .appWillQuit:
                return .run { send in
                    try await chargingClient.turnOnAutoChargingMode()
                    await send(.updateCurrentChargingMode(.charging))
                }
            case let .updatePowerState(powerState):
                state.powerState = powerState
                return changeModeIfNeeded(state: state)
            }
        }
    }

    private func changeModeIfNeeded(state: State) -> Effect<Action> {
        guard let powerState = state.powerState else { return .none }
        guard state.manageCharging else {
            return .run { send in
                try await chargingClient.turnOnAutoChargingMode()
                await send(.updateCurrentChargingMode(.charging))
            }
        }
        return .run { send in
            if state.temperatureSwitch, powerState.batteryTemperature > 35 {
                try await chargingClient.inhibitCharging()
                await send(.updateCurrentChargingMode(.inhibit))
            }
            let currentBatteryLevel = powerState.batteryLevel
            if currentBatteryLevel >= state.chargeLimit {
                if state.allowDischarging,
                   state.lidOpened,
                   !state.computerIsAsleep
                {
                    try await chargingClient.forceDischarge()
                    await send(.updateCurrentChargingMode(.forceDischarge))
                } else if state.enableSystemChargeLimitOnSleep,
                          !state.inhibitChargingOnSleep,
                          state.computerIsAsleep,
                          state.currentChargingMode != .forceCharge
                {
                    try await chargingClient.enableSystemChargeLimit()
                    await send(.updateCurrentChargingMode(.inhibit))

                } else {
                    try await chargingClient.inhibitCharging()
                    await send(.updateCurrentChargingMode(.inhibit))
                }
                await sleepAssertionClient.preventSleepIfNeeded(false)
            } else if state.inhibitChargingOnSleep, !state.enableSystemChargeLimitOnSleep, state.computerIsAsleep, state.currentChargingMode != .forceCharge {
                try await chargingClient.inhibitCharging()
                await send(.updateCurrentChargingMode(.inhibit))
            } else if state.enableSystemChargeLimitOnSleep, !state.inhibitChargingOnSleep, state.computerIsAsleep, state.currentChargingMode != .forceCharge {
                try await chargingClient.enableSystemChargeLimit()
                await send(.updateCurrentChargingMode(.inhibit))
            } else {
                try await chargingClient.turnOnAutoChargingMode()
                await send(.updateCurrentChargingMode(.charging))
                if state.disableSleep {
                    await sleepAssertionClient.preventSleepIfNeeded(true)
                }
            }
        }
    }

}
