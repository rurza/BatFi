//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Charging
import Dependencies
import Foundation

extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient) private var powerSourceClient
        private(set) var state: PowerState? {
            didSet {
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
            Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }
        }

        lazy var timeFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter()
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .short
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
