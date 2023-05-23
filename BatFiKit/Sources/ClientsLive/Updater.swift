//
//  Updater.swift
//  
//
//  Created by Adam on 17/05/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation
import UserNotifications
import Sparkle

extension Updater: DependencyKey {
    public static let liveValue: Updater = {
        let updaterDelegate = UpdaterDelegate()

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: updaterDelegate
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


private class UpdaterDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {

    override init() {
        super.init()
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func updater(_ updater: SPUUpdater, willScheduleUpdateCheckAfterDelay delay: TimeInterval) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _,_ in }
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            let content = UNMutableNotificationContent()
            content.title = "A new update is available"
            content.body = "Version \(update.displayVersionString) is now available"
            let request = UNNotificationRequest(identifier: updateNotificationIdentifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        // Dismiss active update notifications if the user has given attention to the new update
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [updateNotificationIdentifier])
    }

    deinit {

    }
}
