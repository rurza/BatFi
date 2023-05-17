//
//  Updater.swift
//  
//
//  Created by Adam on 17/05/2023.
//

import Clients
import Dependencies
import Foundation
import Sparkle

extension Updater: DependencyKey {
    public static var liveValue: Updater = {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let client = Updater(
            checkForUpdates: {
                updaterController.checkForUpdates(nil)
            },
            automaticallyChecksForUpdates: {
                updaterController.updater.automaticallyChecksForUpdates
            }, automaticallyDownloadsUpdates: {
                updaterController.updater.automaticallyDownloadsUpdates
            },
            setAutomaticallyChecksForUpdates: { check in
                updaterController.updater.automaticallyChecksForUpdates = check

            }, setAutomaticallyDownloadsUpdates: { download in
                updaterController.updater.automaticallyDownloadsUpdates = download
            }
        )
        return client
    }()
}
