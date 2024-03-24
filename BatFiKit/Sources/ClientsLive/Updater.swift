//
//  Updater.swift
//
//
//  Created by Adam on 17/05/2023.
//

import AppShared
import Clients
import Defaults
import Dependencies
import Foundation
import Sparkle
import UserNotifications

extension Updater: DependencyKey {
    public static let liveValue: Updater = {
        let updaterDelegate = UpdaterDelegate.instance

        let updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: updaterDelegate
        )

        let client = Updater(
            checkForUpdates: {
                await updaterController.checkForUpdates(nil)
            },
            automaticallyChecksForUpdates: {
                updaterController.updater.automaticallyChecksForUpdates
            }, automaticallyDownloadsUpdates: {
                updaterController.updater.automaticallyDownloadsUpdates
            },
            setAutomaticallyChecksForUpdates: { check in
                updaterController.updater.automaticallyChecksForUpdates = check
            },
            setAutomaticallyDownloadsUpdates: { download in
                updaterController.updater.automaticallyDownloadsUpdates = download
            },
            setAllowBetaVersion: { allowBeta in
                updaterDelegate.allowBetaVersion = true
            }
        )
        return client
    }()
}

private class UpdaterDelegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    #warning("I don't think it's needed")
    static let instance = UpdaterDelegate()

    var allowBetaVersion = false

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func updater(_: SPUUpdater, willScheduleUpdateCheckAfterDelay _: TimeInterval) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus _: Bool
    ) -> Bool {
        true
    }

    func standardUserDriverWillHandleShowingUpdate(
        _: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            let content = UNMutableNotificationContent()
            content.title = "A new update is available"
            content.body = "Version \(update.displayVersionString) is now available"
            content.interruptionLevel = .active
            let request = UNNotificationRequest(identifier: updateNotificationIdentifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        // Dismiss active update notifications if the user has given attention to the new update
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [updateNotificationIdentifier])
    }

    func allowedChannels(for _: SPUUpdater) -> Set<String> {
        guard allowBetaVersion else { return [] }
        return ["beta"]
    }
}
