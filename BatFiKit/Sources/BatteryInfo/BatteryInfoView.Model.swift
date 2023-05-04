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

        struct Time {
            let value: Int
            let mode: Mode

            enum Mode {
                case timeLeft
                case timeToCharge
            }
        }

        private(set) var time: Time?


        init() {
            state = powerSourceClient.currentPowerSourceState()
            updateTime()
            Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }
        }

        private func updateTime() {
            if state?.isCharging == true {
                self.time = Time(value: state?.timeToCharge ?? 0, mode: .timeToCharge)
            } else {
                if state?.timeLeft ?? 0 != 0 {
                    self.time = Time(value: state?.timeLeft ?? 0, mode: .timeLeft)
                } else {
                    self.time = nil
                }
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
            if let time {
                if time.value > 0 {
                    let interval = Double(time.value) * 60
                    return timeFormatter.string(from: interval)!
                } else {
                    return "Calculating"
                }
            } else {
                return "Unknown"
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
            switch time?.mode {
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
