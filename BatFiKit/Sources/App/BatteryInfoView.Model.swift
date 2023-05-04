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
                updateTimeLeft()
                updateTimeToCharge()
                objectWillChange.send()
            }
        }
        private(set) var timeLeft: String = ""
        private(set) var timeToCharge: String = ""

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


        func updateTimeLeft() {
            if let timeLeft = state?.timeLeft {
                if timeLeft > 0 {
                    let interval = Double(timeLeft) * 60
                    self.timeLeft = timeFormatter.string(from: interval)!
                } else if timeLeft <= 0 {
                    self.timeLeft = "Calculating…"
                }
            } else {
                self.timeLeft = "Unknown"
            }
        }

        func updateTimeToCharge() {
            if let timeToCharge = state?.timeToCharge {
                if timeToCharge > 0 {
                    let interval = Double(timeToCharge) * 60
                    self.timeToCharge = timeFormatter.string(from: interval)!
                } else if timeToCharge <= 0 {
                    self.timeToCharge = "Calculating…"
                }
            } else {
                self.timeToCharge = "Unknown"
            }
        }
    }

}
