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
        @Published public var monochrome: Bool
        @Published public var showPercentage: Bool

        public init(
            chargingMode: ChargingMode,
            batteryLevel: Int,
            monochrome: Bool,
            showPercentage: Bool
        ) {
            self.chargingMode = chargingMode
            self.batteryLevel = batteryLevel
            self.monochrome = monochrome
            self.showPercentage = showPercentage
        }

        public enum ChargingMode: Hashable {
            case charging
            case discharging
            case inhibited
        }
    }
}
