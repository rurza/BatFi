//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Dependencies
import Foundation

extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient) private var powerSourceClient
        @Dependency(\.appChargingState) private var appChargingState
        @Dependency(\.defaults) private var defaults
        @Dependency(\.systemStatsClient) private var systemStatsClient

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
        
        private(set) var topCoalitionInfo: TopCoalitionInfo? {
            willSet {
                objectWillChange.send()
            }
        }
        
        private(set) var batteryChargeGraphInfo: BatteryChargeGraphInfo? {
            willSet {
                objectWillChange.send()
            }
        }

        private var tasks: [Task<Void, Never>]?

        init() {
            self.state = try? powerSourceClient.currentPowerSourceState()
        }

        func setUpObserving() {
            let observeChargingStateMode = Task {
                for await (mode, manageCharging) in combineLatest(
                    appChargingState.observeChargingStateMode(),
                    defaults.observe(.manageCharging)
                ) {
                    if manageCharging {
                        self.modeDescription = mode.stateDescription
                    } else {
                        self.modeDescription = "Disabled"
                    }
                }
            }

            let powerSourceChanges = Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }
            
            let topCoalitionInfoChanges = Task {
                for await info in systemStatsClient.topCoalitionInfoChanges() {
                    self.topCoalitionInfo = info
                }
            }
            
            let batteryChargeGraphInfoChanges = Task {
                for await info in systemStatsClient.batteryChargeGraphInfoChanges() {
                    self.batteryChargeGraphInfo = info
                }
            }

            tasks = [powerSourceChanges, observeChargingStateMode, topCoalitionInfoChanges, batteryChargeGraphInfoChanges]
        }

        func cancelObserving() {
            tasks?.forEach { $0.cancel() }
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
        
        func elapsedTimeDescription() -> String? {
            guard let time = batteryChargeGraphInfo?.batteryStates.last?.time else {
                return nil
            }
            return timeFormatter.string(from: Double(time))
        }
    }
}
