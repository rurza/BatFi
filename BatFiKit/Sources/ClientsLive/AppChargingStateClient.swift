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
        let logger = Logger(category: "🔋")
        let state = AppChargingState.initialState

        let client = AppChargingStateClient(
            updateChargingStateMode: { mode in
                logger.debug("Update charging state mode: \(mode.rawValue, privacy: .public)")
                await state.updateMode(mode)
            },
            observeChargingStateMode: {
                AsyncStream { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.mode)
                        for await note in NotificationCenter.default.notifications(named: chargingModeDidChangeNotificationName) {
                            continuation.yield(note.object as? AppChargingMode)
                        }
                    }

                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .compactMap { $0 }
                .eraseToStream()
            },
            updateLidOpenedStatus: { lidOpened in
                await state.updateLidOpened(lidOpened)
            },
            lidOpened: {
                await state.lidOpened
            },
            chargingStateMode: {
                await state.mode
            }
        )
        return client
    }()
}

private let chargingModeDidChangeNotificationName = Notification.Name("ChargingModeDidChangeNotificationName")

private actor AppChargingState {
    private(set) var mode: AppChargingMode = .initial
    private(set) var lidOpened: Bool?

    static let initialState = AppChargingState(lidOpened: nil)

    init(lidOpened: Bool?) {
        self.lidOpened = lidOpened
    }

    func updateMode(_ mode: AppChargingMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        NotificationCenter.default.post(name: chargingModeDidChangeNotificationName, object: mode)
    }

    func updateLidOpened(_ lidOpened: Bool) {
        guard lidOpened != self.lidOpened else { return }
        self.lidOpened = lidOpened
    }
}
