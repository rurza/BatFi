//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

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

        private lazy var timeFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .short
            formatter.calendar?.locale = locale
            return formatter
        }()

        func timeDescription() -> String {
            switch time?.info {
            case .claculating:
                return "Calculating…"
            case .unknown, .none:
                return "Unknown"
            case .time(let time):
                let interval = Double(time) * 60
                return timeFormatter.string(from: interval)!
            }
        }

        private lazy var temperatureFormatter: MeasurementFormatter = {
            let formatter = MeasurementFormatter()
            formatter.unitStyle = .short
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.maximumFractionDigits = 1
            numberFormatter.locale = locale
            formatter.numberFormatter = numberFormatter
            return formatter
        }()

        func temperatureDescription() -> String? {
            guard let temperature = state?.batteryTemperature else { return nil }
            let measurement = Measurement(value: temperature, unit: UnitTemperature.celsius)
            return temperatureFormatter.string(from: measurement)
        }

        func timeLabel() -> String? {
            switch time?.direction {
            case .timeLeft:
                return "Time Left"
            case .timeToCharge:
                return "Time to Charge"
            case .none:
                return nil
            }
        }
    }
}
