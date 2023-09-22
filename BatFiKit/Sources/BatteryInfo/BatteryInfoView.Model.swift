//
//  BatteryInfoView.Model.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Dependencies
import Foundation
import Shared

extension BatteryInfoView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.powerSourceClient) private var powerSourceClient
        @Dependency(\.appChargingState) private var appChargingState
        @Dependency(\.defaults) private var defaults
        @Dependency(\.powerSettingClient) private var powerSettingClient

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
        
        private(set) var powerSettingInfo: PowerSettingInfo? {
            willSet {
                objectWillChange.send()
            }
        }
        
        var powerModeSelection: PowerMode? {
            get { powerSettingInfo?.powerMode }
            set {
                // Resync picker selection
                objectWillChange.send()
                guard let mode = newValue else {
                    return
                }
                setPowerMode(mode)
            }
        }

        private var tasks: [Task<Void, Never>]?

        init() {
            self.state = try? powerSourceClient.currentPowerSourceState()
        }

        func setUpObserving() {
            let observeChargingStateMode = Task {
                for await (mode, manageCharging) in combineLatest(
                    appChargingState.observeChargingStateMode(),
                    defaults.observe(.manageCharging)
                ) {
                    if manageCharging {
                        self.modeDescription = mode.stateDescription
                    } else {
                        self.modeDescription = "Disabled"
                    }
                }
            }

            let powerSourceChanges = Task {
                for await state in powerSourceClient.powerSourceChanges() {
                    self.state = state
                }
            }
            
            let powerSettingInfoChanges = Task {
                for await info in powerSettingClient.powerSettingInfoChanges() {
                    self.powerSettingInfo = info
                }
            }

            tasks = [powerSourceChanges, observeChargingStateMode, powerSettingInfoChanges]
        }

        func cancelObserving() {
            tasks?.forEach { $0.cancel() }
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
        
        private func setPowerMode(_ mode: PowerMode) {
            guard
                let sourceKey = state?.powerSource,
                let source = PowerSource(key: sourceKey)
            else {
                return
            }
            Task {
                try? await powerSettingClient.setPowerMode(mode, source)
            }
        }
    }
}
