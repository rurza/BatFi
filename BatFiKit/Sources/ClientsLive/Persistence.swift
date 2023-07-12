//
//  Persistence.swift
//  
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import CoreData
import Clients
import Dependencies
import Foundation
import os
import Persistence
import Shared

extension Persistence: DependencyKey {
    public static let liveValue: Persistence = {
        let logger = Logger(category: "💾")
        return Persistence(
            savePowerState: { state, mode in
                try await persistenceContainer.performBackgroundTask { context in
                    logger.debug("Will save a new power state: \(state), mode: \(mode.rawValue)")
                    _ = PowerStateModel(powerState: state, appMode: mode, context: context)
                    try context.save()
                }
            }
        )
    }()
}
