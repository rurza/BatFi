//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Charging
import Dependencies
import Foundation
import PowerSource

extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient) private var powerSourceClient
        @Dependency(\.locale) private var locale
        private(set) var state: PowerState? {
            didSet {
                updateTime()
            }
        }

        private(set) var time: Time?

        init() {
            state = try? powerSourceClient.currentPowerSourceState()
            updateTime()
            Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }
        }

        private func updateTime() {
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
            objectWillChange.send()
        }

        func temperatureDescription() -> String? {
            guard let temperature = state?.batteryTemperature else { return nil }
            let measurement = Measurement(value: temperature, unit: UnitTemperature.celsius)
            return temperatureFormatter.string(from: measurement)
        }
    }
}
