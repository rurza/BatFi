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
                await state.updateMode(mode)
            },
            observeChargingStateMode: {
                AsyncStream(
                    state.objectWillChange
                        .buffer(size: 1, prefetch: .byRequest, whenFull: .dropOldest)
                        .values
                        .compactMap { _ in
                        let value = await state.mode
                        return value
                    }
                )
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
