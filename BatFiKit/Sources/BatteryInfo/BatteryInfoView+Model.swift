//
//  BatteryInfoView+Model.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Dependencies
import Foundation
import Shared

public extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient) private var powerSourceClient
        @Dependency(\.appChargingState) private var appChargingState
        @Dependency(\.defaults) private var defaults
        @Dependency(\.menuDelegate) private var menuDelegate
        @Dependency(\.energyStatsClient) private var energyStatsClient

        private(set) var state: PowerState? {
            didSet {
                updateTime()
            }
        }

        private(set) var time: Time?

        private(set) var modeDescription: String? {
            willSet {
                objectWillChange.send()
            }
        }

        private(set) var batteryChargeGraphInfo: BatteryChargeGraphInfo? {
            willSet {
                objectWillChange.send()
            }
        }

        private var menuTask: Task<Void, Never>?
        private var chargingStateModeChanges: Task<Void, Never>?
        private var powerSourceChanges: Task<Void, Never>?
        private var batteryChargeGraphInfoChanges: Task<Void, Never>?

        public init() {
            Task {
                state = try? await powerSourceClient.currentPowerSourceState()
            }
            menuTask = Task { [weak self] in
                if let menuChanged = await self?.menuDelegate.observeMenu() {
                    for await menuIsOpened in menuChanged {
                        if menuIsOpened {
                            self?.observeChargingStateAndPowerSourceChanges()
                        } else {
                            self?.cancelObserving()
                        }
                    }
                }
            }
        }

        private func observeChargingStateAndPowerSourceChanges() {
            chargingStateModeChanges = Task { [weak self] in
                guard let self else { return }
                for await (mode, manageCharging) in combineLatest(
                    appChargingState.observeChargingStateMode(),
                    defaults.observe(.manageCharging)
                ) {
                    if manageCharging {
                        modeDescription = mode.stateDescription
                    } else {
                        modeDescription = "Disabled"
                    }
                }
            }

            powerSourceChanges = Task { [weak self] in
                guard let self else { return }
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }

            batteryChargeGraphInfoChanges = Task { [weak self] in
                guard let self else { return }
                for await info in energyStatsClient.batteryChargeGraphInfoChanges() {
                    self.batteryChargeGraphInfo = info
                }
            }
        }

        private func cancelObserving() {
            chargingStateModeChanges?.cancel()
            powerSourceChanges?.cancel()
        }

        private func updateTime() {
            objectWillChange.send()
            if let state {
                time = Time(
                    isCharging: state.isCharging,
                    timeLeft: state.timeLeft,
                    timeToCharge: state.timeToCharge,
                    batteryLevel: state.batteryLevel
                )
            } else {
                time = nil
            }
        }

        func temperatureDescription() -> String? {
            guard let temperature = state?.batteryTemperature else { return nil }
            let measurement = Measurement(value: temperature, unit: UnitTemperature.celsius)
            return temperatureFormatter.string(from: measurement)
        }
        
        func elapsedTimeDescription() -> String? {
            guard let time = batteryChargeGraphInfo?.batteryStates.last?.time else {
                return nil
            }
            return timeFormatter.string(from: Double(time))
        }

        deinit {
            chargingStateModeChanges?.cancel()
            chargingStateModeChanges?.cancel()
            powerSourceChanges?.cancel()
            menuTask?.cancel()
        }
    }
}
