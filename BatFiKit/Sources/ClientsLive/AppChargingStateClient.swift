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
                AsyncStream(
                    state.objectWillChange
                    // https://forums.swift.org/t/asyncpublisher-causes-crash-in-rather-simple-situation/56574/4
                        .buffer(size: 1, prefetch: .byRequest, whenFull: .dropOldest)
                        .share()
                        .values
                        .compactMap { _ in
                            let value = await state.mode
                            logger.debug("App charging mode did change: \(value?.rawValue ?? "nil", privacy: .public)")
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


private actor AppChargingState: ObservableObject {

    private(set) var mode: AppChargingMode? {
        didSet { // we want the didSet, so we can read from the object
            objectWillChange.send()
        }
    }
    private(set) var lidOpened: Bool? {
        didSet {
            objectWillChange.send()
        }
    }

    static let initialState = AppChargingState(mode: nil, lidOpened: nil)

    private init(mode: AppChargingMode?, lidOpened: Bool?) {
        self.mode = mode
        self.lidOpened = lidOpened
    }

    func updateMode(_ mode: AppChargingMode) {
        guard mode != self.mode else { return }
        self.mode = mode
    }

    func updateLidOpened(_ lidOpened: Bool) {
        guard lidOpened != self.lidOpened else { return }
        self.lidOpened = lidOpened
    }
}
