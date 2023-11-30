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

extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient)    private var powerSourceClient
        @Dependency(\.appChargingState)     private var appChargingState
        @Dependency(\.defaults)             private var defaults
        @Dependency(\.menuDelegate)         private var menuDelegate

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

        private var menuTask: Task<Void, Never>?
        private var chargingStateModeChanges: Task<Void, Never>?
        private var powerSourceChanges: Task<Void, Never>?


        init() {
            self.state = try? powerSourceClient.currentPowerSourceState()
            menuTask = Task { [weak self] in
                if let menuChanged = await self?.menuDelegate.observeMenu() {
                    for await menuIsOpened in menuChanged {
                        if menuIsOpened {
                            self?.observeChargingStateAndPowerSourceChanges()
                        }
                    }
                }
            }
        }

        private func observeChargingStateAndPowerSourceChanges() {
            cancelObserving()
            chargingStateModeChanges = Task { [weak self] in
                guard let self else { return }
                for await (mode, manageCharging) in combineLatest(
                    self.appChargingState.observeChargingStateMode(),
                    self.defaults.observe(.manageCharging)
                ) {
                    if manageCharging {
                        self.modeDescription = mode.stateDescription
                    } else {
                        self.modeDescription = "Disabled"
                    }
                }
            }

            powerSourceChanges = Task { [weak self] in
                guard let self else { return }
                for await state in self.powerSourceClient.powerSourceChanges() {
                    self.state = state
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
                self.time = Time(
                    isCharging: state.isCharging,
                    timeLeft: state.timeLeft,
                    timeToCharge: state.timeToCharge,
                    batteryLevel: state.batteryLevel
                )
            } else {
                self.time = nil
            }
        }

        func temperatureDescription() -> String? {
            guard let temperature = state?.batteryTemperature else { return nil }
            let measurement = Measurement(value: temperature, unit: UnitTemperature.celsius)
            return temperatureFormatter.string(from: measurement)
        }

        deinit {
            chargingStateModeChanges?.cancel()
            chargingStateModeChanges?.cancel()
            powerSourceChanges?.cancel()
        }
    }
}
