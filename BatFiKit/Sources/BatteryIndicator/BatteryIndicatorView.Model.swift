//
//  BatteryIndicatorView.Model.swift
//
//
//  Created by Adam on 18/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Defaults
import DefaultsKeys
import Dependencies
import Foundation
import SwiftUI

public extension BatteryIndicatorView {
    @MainActor
    final class Model: ObservableObject {
        @Published
        private(set) public var chargingMode: ChargingMode = .discharging
        @Published
        private(set) public var batteryLevel: Int = 0
        @Published
        private(set) public var monochrome: Bool = true
        @Published
        private(set) public var showPercentage: Bool = true

        @Dependency(\.powerSourceClient.powerSourceChanges) 
        private var powerSourceChanges
        @Dependency(\.appChargingState.appChargingModeDidChage)
        private var appChargingModeDidChage
        @Dependency(\.defaults)
        private var defaults
        @Dependency(\.suspendingClock)
        private var clock

        public init() { 
            setUpObserving()
        }

        private func setUpObserving() {
            Task {
                for await ((powerState, mode), (showPercentage, showMonochrome)) in combineLatest(
                    combineLatest(
                        powerSourceChanges(),
                        appChargingModeDidChage()
                    ),
                    combineLatest(
                        defaults.observe(.showBatteryPercentageInStatusIcon),
                        defaults.observe(.monochromeStatusIcon)
                    )
                )
                    .debounce(for: .milliseconds(200), clock: AnyClock(self.clock)) {
                    self.batteryLevel = powerState.batteryLevel
                    self.chargingMode = ChargingMode(appChargingStateMode: mode)
                    self.monochrome = showMonochrome
                    self.showPercentage = showPercentage
                }
            }
        }
    }
}

extension BatteryIndicatorView.Model {
    public enum ChargingMode: Hashable {
        case charging
        case discharging
        case inhibited
        case error

        init(appChargingStateMode: AppChargingMode) {
            guard appChargingStateMode.chargerConnected else {
                self = .discharging
                return
            }
            switch appChargingStateMode.mode {
            case .charging:
                self = .charging
            case .inhibit:
                self = .inhibited
            case .forceDischarge:
                self = .discharging
            case .initial:
                self = .error
            }
        }
    }
}
