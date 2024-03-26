//
//  PersistenceManager.swift
//
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Dependencies
import Foundation
import os
import Shared

public final class PersistenceManager {
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.persistence) private var persistence
    private lazy var logger = Logger(category: "💾👨‍💼")

    public init() {}

    public func setUpObserving() {
        Task {
            for await (state, mode) in combineLatest(
                powerSourceClient.powerSourceChanges(),
                appChargingState.observeChargingStateMode()
            ) {
                do {
                    try await persistence.savePowerState(state, mode)
                } catch {
                    logger.error("Can not save power state: \(state, privacy: .public)\nthe error: \(error, privacy: .public)")
                }
            }
        }
        Task {
            for await _ in await sleepClient.macDidWake() {
                do {
                    let state = try await powerSourceClient.currentPowerSourceState()
                    if let mode = await appChargingState.chargingStateMode() {
                        try await persistence.savePowerState(state, mode)
                    }
                } catch {
                    logger.error("Power source state / persistence error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
