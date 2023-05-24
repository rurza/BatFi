//
//  StatusItemIconController.swift
//  
//
//  Created by Adam on 18/05/2023.
//

import AppShared
import AsyncAlgorithms
import BatteryIndicator
import Clients
import Cocoa
import Dependencies
import DefaultsKeys
import SnapKit
import SwiftUI

@MainActor
public final class StatusItemIconController {
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.settingsDefaultsClient) private var settingsDefaults
    @Dependency(\.suspendingClock) private var clock

    let statusItem: NSStatusItem

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setUpObserving()
    }

    weak var batteryIndicatorView: NSView?
    private lazy var model = BatteryIndicatorView.Model(
        chargingMode: .discharging,
        batteryLevel: 0,
        monochrome: true,
        showPercentage: true
    )

    func setUpObserving() {
        Task {
            for await ((powerState, mode), (showPercentage, showMonochrome))  in combineLatest(
                combineLatest(
                    powerSourceClient.powerSourceChanges(),
                    appChargingState.observeChargingStateMode()
                ),
                combineLatest(
                    settingsDefaults.observeShowBatteryPercentage(),
                    settingsDefaults.observeShowMonochromeIcon()
                ))
                .debounce(for: .milliseconds(200), clock: AnyClock(self.clock)) {
                model.batteryLevel = powerState.batteryLevel
                model.chargingMode = BatteryIndicatorView.Model.ChargingMode(appChargingStateMode: mode)
                model.monochrome = showMonochrome
                model.showPercentage = showPercentage
                guard let button = statusItem.button else { continue }
                if batteryIndicatorView == nil {
                    let hostingView = NSHostingView(rootView: BatteryIndicatorView(model: self.model))
                    hostingView.translatesAutoresizingMaskIntoConstraints = false
                    hostingView.wantsLayer = true
                    button.addSubview(hostingView)
                    hostingView.snp.makeConstraints { make in
                        make.centerX.equalToSuperview().offset(3) // offset by the "nipple" so the battery will look centered
                        make.width.equalTo(33)
                        make.height.equalTo(13)
                        make.centerY.equalToSuperview()
                    }
                    button.snp.makeConstraints { make in
                        make.width.equalTo(38)
                        make.centerX.equalToSuperview()
                    }
                    self.batteryIndicatorView = hostingView
                }
            }
        }
    }
}

extension BatteryIndicatorView.Model.ChargingMode {
    init(appChargingStateMode: AppChargingMode) {
        switch appChargingStateMode {
        case .charging, .forceCharge:
            self = .charging
        case .inhibit:
            self = .inhibited
        case .forceDischarge, .disabled, .chargerNotConnected:
            self = .discharging
        }
    }
}
