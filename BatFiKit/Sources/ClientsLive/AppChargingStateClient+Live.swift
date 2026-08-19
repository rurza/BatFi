//
//  AppChargingStateClient.swift
//
//
//  Created by Adam on 16/05/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation
import os
import Shared

extension AppChargingStateClient: DependencyKey {
    public static let liveValue: AppChargingStateClient = {
        let logger = Logger(category: "App Charging State")
        let state = AppChargingState.initialState
        logger.debug("Creating a new charging state client")
        let client = AppChargingStateClient(
            updateLidOpenedStatus: { lidIsOpened in
                await state.updateLidOpened(lidIsOpened)
            },
            lidOpened: {
                await state.lidOpened
            },
            appChargingModeDidChage: {
                AsyncStream<AppChargingMode?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.mode)
                        for await note in NotificationCenter.default.notifications(named: ChargingModeDidChangeNotificationName) {
                            let object = note.object as? AppChargingMode
                            continuation.yield(object)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .compactMap { $0 }
                .eraseToStream()
            },
            currentAppChargingMode: {
                await state.mode
            },
            setAppChargingMode: { mode in
                await state.setAppChargingMode(mode)
            },
            userTempOverrideDidChange: {
                AsyncStream<UserTempChargingMode?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.mode.userTempOverride)
                        for await note in NotificationCenter.default.notifications(named: UserTempChargingModeDidChangeNotificationName) {
                            let object = note.object as? UserTempChargingMode
                            continuation.yield(object)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .eraseToStream()
            },
            currentUserTempOverrideMode: {
                await state.mode.userTempOverride
            },
            updateChargingMode: { mode in
                await state.updateMode(mode)
            },
            setSystemChargeHold: { draining, holdingBelowLimit in
                await state.updateSystemChargeHold(draining: draining, holdingBelowLimit: holdingBelowLimit)
            },
            setTempOverride: { mode in
                await state.updateOverride(mode)
            },
            setChargerConnected: { connected in
                await state.updateChargerConnected(connected)
            },
            setAutomationLimit: { limit in
                await state.updateAutomationLimit(limit)
            },
            currentAutomationLimit: {
                await state.automationLimit
            },
            automationLimitDidChange: {
                AsyncStream<Int?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.automationLimit)
                        for await note in NotificationCenter.default.notifications(named: AutomationLimitDidChangeNotificationName) {
                            continuation.yield(note.object as? Int)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .eraseToStream()
            }
        )
        return client
    }()
}

private let ChargingModeDidChangeNotificationName = Notification.Name("ChargingModeDidChangeNotificationName")
private let UserTempChargingModeDidChangeNotificationName = Notification.Name("UserTempChargingModeDidChangeNotificationName")
private let AutomationLimitDidChangeNotificationName = Notification.Name("AutomationLimitDidChangeNotificationName")

private actor AppChargingState {
    private(set) var mode: AppChargingMode = .init(mode: .initial, userTempOverride: nil, chargerConnected: false)
    private(set) var userTempChargingMode: UserTempChargingMode? = nil
    private(set) var lidOpened: Bool?
    private(set) var automationLimit: Int?

    static let initialState = AppChargingState(lidOpened: nil)

    init(lidOpened: Bool?) {
        self.lidOpened = lidOpened
    }

    func setAppChargingMode(_ mode: AppChargingMode) {
        guard mode != self.mode else { return }
        let oldMode = self.mode
        self.mode = mode
        NotificationCenter.default.post(name: ChargingModeDidChangeNotificationName, object: mode)
        if mode.userTempOverride != oldMode.userTempOverride {
            NotificationCenter.default.post(name: UserTempChargingModeDidChangeNotificationName, object: mode.userTempOverride)
        }
    }

    // `updateSystemChargeHold` is the only writer of those flags. The three around it carry
    // them across rather than letting them default back to `false`: none of them is told
    // anything about the drain or the hold, and dropping them would relabel a Mac mid-drain as
    // "Inhibiting charging" on the next charger-connection update — which the appliers issue
    // on every pass, i.e. throughout the drain.

    func updateMode(_ newMode: ChargingMode) {
        let newAppChargingMode = AppChargingMode(
            mode: newMode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: mode.systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: mode.systemIsHoldingBelowLimit
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateSystemChargeHold(draining: Bool, holdingBelowLimit: Bool) {
        guard draining != mode.systemIsDischargingToLimit
            || holdingBelowLimit != mode.systemIsHoldingBelowLimit else { return }
        let newAppChargingMode = AppChargingMode(
            mode: mode.mode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: draining,
            systemIsHoldingBelowLimit: holdingBelowLimit
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateOverride(_ override: UserTempChargingMode?) {
        let newAppChargingMode = AppChargingMode(
            mode: mode.mode,
            userTempOverride: override,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: mode.systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: mode.systemIsHoldingBelowLimit
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateChargerConnected(_ connected: Bool) {
        let newAppChargingMode = AppChargingMode(
            mode: mode.mode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: connected,
            systemIsDischargingToLimit: mode.systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: mode.systemIsHoldingBelowLimit
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateLidOpened(_ lidOpened: Bool) {
        guard lidOpened != self.lidOpened else { return }
        self.lidOpened = lidOpened
    }

    func updateAutomationLimit(_ limit: Int?) {
        guard limit != automationLimit else { return }
        automationLimit = limit
        NotificationCenter.default.post(name: AutomationLimitDidChangeNotificationName, object: limit)
    }

}
