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
    /// False until the first successful power source read. Without this, a failed read is
    /// indistinguishable from a genuine 0% battery.
    @Published
    public var hasReading: Bool = false
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
                self.hasReading = true
                self.chargingMode = ChargingMode(appChargingMode: mode)
                self.monochrome = showMonochrome
                self.showPercentage = showPercentage
                self.showPercentageNextToIndicator = showPercentageOnBatteryIcon
            }
        }
    }
}

extension BatteryIndicatorViewModel {
    /// Lives in `AppShared`, where a test target can reach the mapping. The name stays for
    /// the call sites — the views and the Previews app both spell it this way.
    public typealias ChargingMode = BatteryIndicatorMode
}
