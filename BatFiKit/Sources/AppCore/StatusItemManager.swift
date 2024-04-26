//
//  StatusItemManager.swift
//
//
//  Created by Adam on 18/05/2023.
//

import AppShared
import AsyncAlgorithms
import BatteryIndicator
import Combine
import Clients
import Cocoa
import DefaultsKeys
import Dependencies
import SnapKit
import SwiftUI

@MainActor
public protocol StatusItemManagerDelegate: AnyObject {
    func statusItemIconDidAppear()
}

@MainActor
public final class StatusItemManager {
    public weak var delegate: StatusItemManagerDelegate?

    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.defaults) private var defaults
    @Dependency(\.suspendingClock) private var clock
    private var didAppear = false

    let statusItem: NSStatusItem

    public init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        setUpObserving()
    }

    weak var batteryIndicatorView: NSView?
    private lazy var batteryIndicatorModel = BatteryIndicatorView.Model(
        chargingMode: .discharging,
        batteryLevel: 0,
        monochrome: true,
        showPercentage: true
    )

    private var statusItemModel: StatusItemModel?

    private var sizePassthrough = PassthroughSubject<CGSize, Never>()
    private var sizeCancellable: AnyCancellable?

    func setUpObserving() {
        Task {
            for await ((powerState, mode), (showPercentage, showMonochrome)) in combineLatest(
                combineLatest(
                    powerSourceClient.powerSourceChanges(),
                    appChargingState.appChargingModeDidChage()
                ),
                combineLatest(
                    defaults.observe(.showBatteryPercentageInStatusIcon),
                    defaults.observe(.monochromeStatusIcon)
                )
            )
            .debounce(for: .milliseconds(200), clock: AnyClock(self.clock)) {
                batteryIndicatorModel.batteryLevel = powerState.batteryLevel
                batteryIndicatorModel.chargingMode = BatteryIndicatorView.Model.ChargingMode(appChargingStateMode: mode)
                batteryIndicatorModel.monochrome = showMonochrome
                batteryIndicatorModel.showPercentage = showPercentage
                statusItemModel?.powerState = powerState

                guard let button = statusItem.button else { continue }
                if batteryIndicatorView == nil {
                    statusItemModel = StatusItemModel(powerState: powerState)
                    let hostingView = NSHostingView(
                        rootView: StatusItem(
                            sizePassthrough: sizePassthrough,
                            batteryIndicatorModel: batteryIndicatorModel,
                            model: statusItemModel!
                        )
                    )
                    hostingView.frame = NSRect(x: 0, y: 0, width: 38, height: 13)
                    button.frame = hostingView.frame
                    hostingView.wantsLayer = true
                    button.addSubview(hostingView)
                    self.batteryIndicatorView = hostingView
                    sizeCancellable = sizePassthrough.sink { [weak self] size in
                        let frame = NSRect(origin: .zero, size: .init(width: size.width, height: 24))
                        self?.batteryIndicatorView?.frame = frame
                        self?.statusItem.button?.frame = frame
                    }
                }
                if !didAppear {
                    didAppear = true
                    delegate?.statusItemIconDidAppear()
                }
            }
        }
    }

    @ViewBuilder
    func indicatorView(powerState: PowerState) -> some View {
        HStack {
            Text("\(powerState.timeLeft)")
            BatteryIndicatorView(model: self.batteryIndicatorModel)
                .frame(width: 33)
        }
    }
}

extension BatteryIndicatorView.Model.ChargingMode {
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
