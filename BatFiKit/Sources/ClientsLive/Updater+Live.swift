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

    /// Whether the notification below can actually reach the user.
    ///
    /// It decides who shows a scheduled update, so it starts at `false`: until this is
    /// known, Sparkle keeps showing its own window, which is what shipped. Being wrong in
    /// that direction costs an unfocused window; being wrong in the other direction means
    /// an update nobody is told about at all.
    private var canPostNotifications = false

    func updater(_: SPUUpdater, willScheduleUpdateCheckAfterDelay _: TimeInterval) {
        // Answers with the standing decision when there already is one, so a user who
        // denied notifications long ago is recognised here rather than assumed reachable.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor [weak self] in self?.canPostNotifications = granted }
        }
    }

    /// Who shows a *scheduled* update: Sparkle, or the notification below.
    ///
    /// This answered `true` unconditionally, which asked for both. Sparkle's standard
    /// driver will not activate a background app for a scheduled check — it shows the
    /// alert without focus, or orders it behind the app's own windows — so every
    /// background check put an unfocused changelog window on screen *and* posted a
    /// notification about it. The window could not be typed into, was not key, and was
    /// usually somewhere behind whatever the user was working in.
    ///
    /// Answering `immediateFocus` hands Sparkle only the cases where it intends to show
    /// the update in focus and will activate the app to do it — near launch, or when the
    /// machine has been idle long enough that nobody is being interrupted. Everywhere
    /// else the notification is the whole reminder, and clicking it runs
    /// `checkForUpdates()` from `NotificationsManager`, which is Sparkle's documented way
    /// to bring the alert up as a user-initiated check: activated, key, focused.
    ///
    /// Unless the notification cannot be delivered, in which case Sparkle has to keep
    /// showing the window. Handing the reminder to a notification the user has switched
    /// off would trade a window that is merely in the wrong place for an update they are
    /// never told about.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus || !canPostNotifications
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
