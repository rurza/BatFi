//
//  BatteryInfoView+Model.swift
//
//
//  Created by Adam on 02/05/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Dependencies
import Foundation
import L10n
import Shared

@MainActor
public final class BatteryInfoViewModel: ObservableObject {
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.defaults) private var defaults
    @Dependency(\.menuDelegate) private var menuDelegate
    @Dependency(\.energyStatsClient) private var energyStatsClient
    @Dependency(\.persistence) private var persistence
    @Dependency(\.date) private var date

    @Published
    private(set) public var state: PowerState?

    @Published
    private var dischargeDate: Date?

    var dischargeDateRelativeTime: String? { dischargeDate?.relativeTime(to: date.now) }

    @Published
    private var fullChargeDate: Date?

    var fullChargeDateRelativeTime: String? { fullChargeDate?.relativeTime(to: date.now) }

    var time: Time? {
        guard let state else { return nil }
        return Time(
            isCharging: state.isCharging,
            timeLeft: state.timeLeft,
            timeToCharge: state.timeToCharge,
            batteryLevel: state.batteryLevel
        )
    }

    private(set) var modeDescription: String? {
        willSet {
            objectWillChange.send()
        }
    }

    private(set) var batteryChargeGraphInfo: BatteryChargeGraphInfo? {
        willSet {
            objectWillChange.send()
        }
    }

    private var menuTask: Task<Void, Never>?
    private var chargingStateModeChanges: Task<Void, Never>?
    private var powerSourceChanges: Task<Void, Never>?
    private var batteryChargeGraphInfoChanges: Task<Void, Never>?

    public init() {
        Task { [weak self] in
            self?.state = try? await self?.powerSourceClient.currentPowerSourceState()
        }
        menuTask = Task { [weak self] in
            if let menuChanged = await self?.menuDelegate.observeMenu() {
                for await menuIsOpened in menuChanged {
                    if menuIsOpened {
                        self?.observeChargingStateAndPowerSourceChanges()
                    } else {
                        self?.cancelObserving()
                    }
                }
            }
        }
    }

    private func observeChargingStateAndPowerSourceChanges() {
        chargingStateModeChanges = Task { [weak self] in
            guard let self else { return }
            for await (mode, manageCharging) in combineLatest(
                appChargingState.appChargingModeDidChage(),
                defaults.observe(.manageCharging)
            ) {
                if manageCharging {
                    modeDescription = mode.stateDescription
                } else {
                    modeDescription = L10n.AppChargingMode.State.Title.disabled
                }
            }
        }

        powerSourceChanges = Task { [weak self] in
            guard let self else { return }
            for await state in powerSourceClient.powerSourceChanges() {
                self.state = state
            }
        }

        batteryChargeGraphInfoChanges = Task { [weak self] in
            guard let self else { return }
            for await info in energyStatsClient.batteryChargeGraphInfoChanges() {
                self.batteryChargeGraphInfo = info
            }
        }
    }

    private func cancelObserving() {
        chargingStateModeChanges?.cancel()
        powerSourceChanges?.cancel()
        batteryChargeGraphInfoChanges?.cancel()
    }

    func temperatureDescription() -> String? {
        guard let temperature = state?.batteryTemperature else { return nil }
        let measurement = Measurement(value: temperature, unit: UnitTemperature.celsius)
        return temperatureFormatter.string(from: measurement)
    }

    func elapsedTimeDescription() -> String? {
        guard let time = batteryChargeGraphInfo?.batteryStates.last?.time else {
            return nil
        }
        return timeFormatter.string(from: Double(time))
    }

    func batteryPercentageDescription() -> String? {
        guard let percentage = state?.batteryLevel else { return nil }
        let doubleValue = Double(percentage) / 100.0
        return percentageFormatter.string(for: doubleValue)
    }

    func batteryHealthDescription() -> String? {
        guard let percentage = state?.batteryHealth else { return nil }
        let doubleValue = Double(percentage) / 100.0
        return percentageFormatter.string(for: doubleValue)
    }

    func viewDidAppear() {
        Task { @MainActor [weak self] in
            self?.dischargeDate = try? await self?.persistence.fetchLastDischargeDate()
            self?.fullChargeDate = try? await self?.persistence.fetchLastFullChargeDate()
        }
    }
    
    deinit {
        chargingStateModeChanges?.cancel()
        batteryChargeGraphInfoChanges?.cancel()
        powerSourceChanges?.cancel()
        menuTask?.cancel()
    }
}
