//
//  AppThrottleClient+Live.swift
//  BatFi
//
//  The live Mac behind "Slow down on battery" and Quit: the process table, the running
//  apps, the app in front, audio activity, and the two calls that act on apps.
//

import AppKit
import AppShared
import Clients
import Darwin
import Dependencies
import os
import Shared

extension AppThrottleClient: DependencyKey {
    public static let liveValue: AppThrottleClient = {
        let logger = Logger(category: "App Throttle")
        let processTable = ProcessTableReader()
        let ownBundleIDs = Set([Constant.appBundleIdentifier, Bundle.main.bundleIdentifier].compactMap { $0 })
        let quits = QuitAnnouncements()
        let reports = SlowDownReports()

        return AppThrottleClient(
            processSnapshot: {
                let table = processTable.snapshot()
                if table.isEmpty {
                    logger.notice("The process table could not be read whole.")
                }
                return table
            },
            runningApps: {
                await MainActor.run { RunningApps.records(ownBundleIDs: ownBundleIDs) }
            },
            frontmostChanges: {
                WorkspaceNotifications.stream(
                    of: [NSWorkspace.didActivateApplicationNotification],
                    current: { RunningApps.frontmost(NSWorkspace.shared.frontmostApplication) },
                    element: { note in
                        RunningApps.frontmost(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
                    }
                )
            },
            runningAppsChanges: {
                WorkspaceNotifications.stream(
                    of: [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification],
                    current: nil,
                    element: { _ in () },
                    // A signal to look again: one unread is as good as several.
                    bufferingPolicy: .bufferingNewest(1)
                )
            },
            audioActivePIDs: {
                AudioProcesses.activePIDs()
            },
            audioActivityChanges: {
                // A signal to look again: one unread is as good as several.
                AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
                    let watcher = AudioActivityWatcher { continuation.yield() }
                    watcher.start()
                    continuation.onTermination = { _ in watcher.stop() }
                }
            },
            setBackground: { pid, background in
                ThrottleResult.applying(to: pid) { pid in
                    setpriority(PRIO_DARWIN_PROCESS, pid, background ? PRIO_DARWIN_BG : 0)
                }
            },
            terminate: { bundleID in
                await MainActor.run {
                    let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    // Each instance is asked as its Quit menu item would ask it; one that has
                    // already gone counts as asked.
                    let asked = instances.map { $0.terminate() || $0.isTerminated }
                    logger.notice("Asked \(bundleID, privacy: .public) to quit: \(asked.filter { $0 }.count, privacy: .public) of \(instances.count, privacy: .public) instances.")
                    return !instances.isEmpty && !asked.contains(false)
                }
            },
            willAskToQuit: { bundleID in
                quits.announce(bundleID)
            },
            quitAnnouncements: {
                quits.stream()
            },
            publishSlowDownReport: { next in
                reports.publish(next)
            },
            slowDownReportChanges: {
                reports.stream()
            }
        )
    }()
}

/// Hands each app about to be asked to quit to every stream open at the time. Delivered
/// into each stream before `announce` returns, so a quit asked right after it cannot
/// overtake it. In this process only.
private final class QuitAnnouncements: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<String>.Continuation] = [:]

    func stream() -> AsyncStream<String> {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            lock.withLock { _ = continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func announce(_ bundleID: String) {
        let open = lock.withLock { Array(continuations.values) }
        for continuation in open {
            continuation.yield(bundleID)
        }
    }
}

/// The slow-down report, as the throttle manager last published it, handed to every stream
/// open at the time. In this process only.
private final class SlowDownReports: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SlowDownReport?
    private var continuations: [UUID: AsyncStream<SlowDownReport?>.Continuation] = [:]

    /// Starts with the report as it is now. Only the newest unread value is kept.
    func stream() -> AsyncStream<SlowDownReport?> {
        let (stream, continuation) = AsyncStream<SlowDownReport?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        // Registered and seeded under one lock, so that a publish cannot fall in between.
        lock.withLock {
            continuations[id] = continuation
            continuation.yield(current)
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            lock.withLock { _ = continuations.removeValue(forKey: id) }
        }
        return stream
    }

    func publish(_ next: SlowDownReport) {
        lock.withLock {
            guard next != current else { return }
            current = next
            // Under the lock, so that every stream sees the reports in the order published.
            for continuation in continuations.values {
                continuation.yield(next)
            }
        }
    }
}

/// The running apps, as `NSWorkspace` lists them.
@MainActor
private enum RunningApps {
    /// Every running app that has a bundle identifier and a process.
    static func records(ownBundleIDs: Set<String>) -> [RunningAppRecord] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier, app.processIdentifier > 0 else { return nil }
            let isRegular = app.activationPolicy == .regular
            return RunningAppRecord(
                bundleID: bundleID,
                pid: app.processIdentifier,
                // Offered for apps with a Dock icon only. Accessory and prohibited "apps" are
                // mostly parts of another one: WebContent, helpers, open and save panels.
                isEligible: isRegular && ThrottleEligibility.canOfferActions(
                    bundleID: bundleID,
                    bundleURL: app.bundleURL,
                    ownBundleIDs: ownBundleIDs
                ),
                isRegular: isRegular
            )
        }
    }

    static func frontmost(_ app: NSRunningApplication?) -> (pid: pid_t?, bundleID: String?) {
        let pid = app?.processIdentifier
        return (pid.flatMap { $0 > 0 ? $0 : nil }, app?.bundleIdentifier)
    }
}

/// Streams built on `NSWorkspace`'s notifications.
private enum WorkspaceNotifications {
    /// An element for each of these notifications, preceded by `current` where given, until
    /// the stream ends.
    static func stream<Element: Sendable>(
        of names: [Notification.Name],
        current: (@MainActor @Sendable () -> Element)?,
        element: @escaping @MainActor @Sendable (Notification) -> Element,
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) -> AsyncStream<Element> {
        AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            let observers = ObserverTokens()
            Task { @MainActor in
                let center = NSWorkspace.shared.notificationCenter
                let tokens = names.map { name in
                    center.addObserver(forName: name, object: nil, queue: .main) { note in
                        // Delivered on the main queue, and handed nowhere else.
                        nonisolated(unsafe) let note = note
                        MainActor.assumeIsolated { _ = continuation.yield(element(note)) }
                    }
                }
                // Read after observing, so that a change landing in between still arrives.
                if let current { continuation.yield(current()) }
                observers.hold(tokens, in: center)
            }
            continuation.onTermination = { _ in observers.release() }
        }
    }
}

/// The observers behind one stream, removed when it ends — including when it ends before
/// they were added.
private final class ObserverTokens: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [NSObjectProtocol] = []
    private var center: NotificationCenter?
    private var hasEnded = false

    func hold(_ tokens: [NSObjectProtocol], in center: NotificationCenter) {
        let hasEnded = lock.withLock {
            if !self.hasEnded {
                self.tokens = tokens
                self.center = center
            }
            return self.hasEnded
        }
        if hasEnded { tokens.forEach(center.removeObserver) }
    }

    func release() {
        let (tokens, center) = lock.withLock {
            hasEnded = true
            defer {
                self.tokens = []
                self.center = nil
            }
            return (self.tokens, self.center)
        }
        tokens.forEach { center?.removeObserver($0) }
    }
}
