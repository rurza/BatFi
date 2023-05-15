//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import Combine
import Clients
import Dependencies
import Foundation

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

        private(set) var modeDescription: String? {
            willSet {
                objectWillChange.send()
            }
        }

        private var cancellables = Set<AnyCancellable>()

        init() {
            Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }

            AppChargingState.shared.objectWillChange.sink { [weak self] _ in
                Task {
                    let description = await AppChargingState.shared.mode?.stateDescription
                    self?.modeDescription = description
                }
            }
            .store(in: &cancellables)
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
