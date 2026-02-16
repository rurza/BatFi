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
import os.log
import SwiftUI

// a lot of properties is public because I want to easily test it from the Previews app
@MainActor
public final class BatteryIndicatorViewModel: ObservableObject {
    @Published
    public var chargingMode: ChargingMode = .discharging
    @Published
    public var batteryLevel: Int = 0
    @Published
    public var monochrome: Bool = Defaults[.monochromeStatusIcon]
    @Published
    public var showPercentage: Bool = Defaults[.showBatteryPercentageInStatusIcon]
    @Published
    public var showPercentageNextToIndicator: Bool = Defaults[.showPercentageOnBatteryIcon]

    @Dependency(\.powerSourceClient.powerSourceChanges)
    private var powerSourceChanges
    @Dependency(\.appChargingState.appChargingModeDidChage)
    private var appChargingModeDidChage
    @Dependency(\.defaults)
    private var defaults
    @Dependency(\.suspendingClock)
    private var clock

    private lazy var logger = Logger(category: "BatteryInfdicatorView.Model")

    public init() {
        setUpObserving()
    }

    private func setUpObserving() {
        Task {
            for await ((powerState, mode), (showPercentage, showMonochrome, showPercentageOnBatteryIcon)) in combineLatest(
                combineLatest(
                    powerSourceChanges(),
                    appChargingModeDidChage()
                ),
                combineLatest(
                    defaults.observe(.showBatteryPercentageInStatusIcon),
                    defaults.observe(.monochromeStatusIcon),
                    defaults.observe(.showPercentageOnBatteryIcon)
                )
            ) {
                logger.debug("Update battery indicator: \(powerState)")
                self.batteryLevel = powerState.batteryLevel
                self.chargingMode = ChargingMode(appChargingStateMode: mode)
                self.monochrome = showMonochrome
                self.showPercentage = showPercentage
                self.showPercentageNextToIndicator = showPercentageOnBatteryIcon
            }
        }
    }
}

extension BatteryIndicatorViewModel {
    public enum ChargingMode: Hashable {
        case charging
        case discharging
        case inhibited
        case error

        init(appChargingStateMode: AppChargingMode) {
            guard appChargingStateMode.mode != .initial else {
                self = .error
                return
            }
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
