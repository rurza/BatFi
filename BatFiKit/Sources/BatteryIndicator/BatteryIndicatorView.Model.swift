//
//  BatteryIndicatorView.Model.swift
//  
//
//  Created by Adam on 18/05/2023.
//

import Foundation

public extension BatteryIndicatorView {
    final class Model: ObservableObject {
        @Published public var chargingMode: ChargingMode
        @Published public var batteryLevel: Int
        @Published public var monochrome: Bool = false

        public init(chargingMode: ChargingMode, batteryLevel: Int) {
            self.chargingMode = chargingMode
            self.batteryLevel = batteryLevel
        }

        public enum ChargingMode: Hashable {
            case charging
            case discharging
            case inhibited
        }
    }
}
