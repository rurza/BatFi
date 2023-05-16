//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation

extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient) private var powerSourceClient
        @Dependency(\.appChargingState) private var appChargingState
        @Dependency(\.locale) private var locale


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

        init() {
            Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }

            Task {
                for await mode in appChargingState.observeChargingStateMode() {
                    self.modeDescription = mode.stateDescription
                }
            }
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
    }
}
