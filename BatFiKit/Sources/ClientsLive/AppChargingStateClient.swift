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
            setTempOverride: { mode in
                await state.updateOverride(mode)
            },
            setChargerConnected: { connected in
                await state.updateChargerConnected(connected)
            }
        )
        return client
    }()
}

private let ChargingModeDidChangeNotificationName = Notification.Name("ChargingModeDidChangeNotificationName")
private let UserTempChargingModeDidChangeNotificationName = Notification.Name("UserTempChargingModeDidChangeNotificationName")

private actor AppChargingState {
    private(set) var mode: AppChargingMode = .init(mode: .initial, userTempOverride: nil, chargerConnected: false)
    private(set) var userTempChargingMode: UserTempChargingMode? = nil
    private(set) var lidOpened: Bool?

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

    func updateMode(_ newMode: ChargingMode) {
        let newAppChargingMode = AppChargingMode(
            mode: newMode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateOverride(_ override: UserTempChargingMode?) {
        let newAppChargingMode = AppChargingMode(mode: mode.mode, userTempOverride: override, chargerConnected: mode.chargerConnected)
        setAppChargingMode(newAppChargingMode)
    }

    func updateChargerConnected(_ connected: Bool) {
        let newAppChargingMode = AppChargingMode(mode: mode.mode, userTempOverride: mode.userTempOverride, chargerConnected: connected)
        setAppChargingMode(newAppChargingMode)
    }

    func updateLidOpened(_ lidOpened: Bool) {
        guard lidOpened != self.lidOpened else { return }
        self.lidOpened = lidOpened
    }

}
