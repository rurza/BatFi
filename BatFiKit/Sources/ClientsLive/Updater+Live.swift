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
import L10n
import Sparkle
import UserNotifications

extension Updater: DependencyKey {
    public static let liveValue = Updater(
        startUpdater: {
            Task { @MainActor in _ = SparkleUpdater.shared }
        },
        checkForUpdates: {
            Task { @MainActor in SparkleUpdater.shared.controller.checkForUpdates(nil) }
        },
        automaticallyChecksForUpdates: {
            SparkleUpdater.shared.controller.updater.automaticallyChecksForUpdates
        },
        automaticallyDownloadsUpdates: {
            SparkleUpdater.shared.controller.updater.automaticallyDownloadsUpdates
        },
        setAutomaticallyChecksForUpdates: { check in
            Task { @MainActor in
                SparkleUpdater.shared.controller.updater.automaticallyChecksForUpdates = check
            }
        },
        setAutomaticallyDownloadsUpdates: { download in
            Task { @MainActor in
                SparkleUpdater.shared.controller.updater.automaticallyDownloadsUpdates = download
            }
        }
    )
}

/// Owns the one Sparkle controller for the process.
///
/// Sparkle has been main-thread-only since 2.8 and says so in its headers as of 2.9, so
/// the controller is built and touched here and nowhere else. The delegate is held
/// strongly because Sparkle does not.
@MainActor
private final class SparkleUpdater {
    static let shared = SparkleUpdater()

    let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: delegate
        )
    }
}

@MainActor
private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate, @MainActor SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool {
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
            content.title = L10n.Updater.Notification.updateAvailable
            content.body = L10n.Updater.Notification.updateAvailableBody(update.displayVersionString)
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
        guard Defaults[.downloadBetaVersion] else { return [] }
        return ["beta"]
    }
}
