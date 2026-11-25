//
//  AppThrottleClient.swift
//  BatFi
//
//  What BatFi reads from the Mac, and asks of it, to slow apps down on battery and to quit
//  them.
//

import AppShared
import Dependencies
import DependenciesMacros
import Foundation

/// The Mac as the "Slow down on battery" feature sees it, and the two things it does to apps.
///
/// Nothing here polls or keeps anything running on its own: the reads answer when asked, and
/// the change streams only relay what macOS announces. When to look again is the caller's
/// decision.
@DependencyClient
public struct AppThrottleClient: Sendable {
    /// Every process BatFi's user runs, together with launchd, each with its resource
    /// coalition where that could be read.
    ///
    /// Either the whole table or none: an empty array where it could not be read whole,
    /// never part of one, since the policy would take a missing process for an exited one.
    public var processSnapshot: @Sendable () async -> [ProcessRecord] = { [] }
    /// Every running app with a bundle identifier, whatever its activation policy.
    public var runningApps: @Sendable () async -> [RunningAppRecord] = { [] }
    /// The app in front, first as it is now, then each time another one comes to the front.
    public var frontmostChanges: @Sendable () -> AsyncStream<(pid: pid_t?, bundleID: String?)> = {
        AsyncStream { $0.finish() }
    }
    /// Announces each app launched or quit. macOS announces apps with a Dock icon only, not
    /// accessory or background ones. Announcements that arrive while the last one is still
    /// unread are folded into it.
    public var runningAppsChanges: @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
    /// The processes playing or recording audio right now, or nil where that could not be
    /// told. Nil is not silence: the caller must keep the set it had, since taking a playing
    /// process for a silent one would slow it down and break up its sound.
    public var audioActivePIDs: @Sendable () async -> Set<pid_t>? = { nil }
    /// Announces each time a process starts or stops playing or recording audio, or a
    /// process connects to or leaves the audio system. Announcements that arrive while the
    /// last one is still unread are folded into it.
    public var audioActivityChanges: @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
    /// Confines the process to the efficiency cores and lowers its disk and network
    /// priority (`true`), or gives it back (`false`).
    public var setBackground: @Sendable (_ pid: pid_t, _ background: Bool) async -> ThrottleResult = { _, _ in
        .failed(ENOSYS)
    }
    /// Asks every running instance of the app to quit, as its Quit menu item would. Never
    /// forces it. False where no instance was running, or one could not be asked.
    public var terminate: @Sendable (_ bundleID: String) async -> Bool = { _ in false }
    /// Says, within BatFi, that the app is about to be asked to quit, so that the throttle
    /// manager gives it back and leaves it alone while it quits: a slowed app can be too
    /// starved to answer. Call it before `terminate`.
    public var willAskToQuit: @Sendable (_ bundleID: String) -> Void = { _ in }
    /// Each app about to be asked to quit, as `willAskToQuit` says it, from when the stream
    /// is made until it ends.
    public var quitAnnouncements: @Sendable () -> AsyncStream<String> = { AsyncStream { $0.finish() } }
    /// Says, within BatFi, whether the Mac is on its battery, whether the licence is active,
    /// and whether each app in the list of apps slowed down on battery is slowed right now,
    /// and if not, why. The throttle manager calls it after each pass; nothing is persisted, so a new launch starts with no
    /// report.
    public var publishSlowDownReport: @Sendable (_ report: SlowDownReport) -> Void = { _ in }
    /// The report `publishSlowDownReport` last made, first as it is now — nil before the
    /// first pass — then each time it changes, until the stream ends.
    public var slowDownReportChanges: @Sendable () -> AsyncStream<SlowDownReport?> = {
        AsyncStream { $0.finish() }
    }
}

extension AppThrottleClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: AppThrottleClient = .init()
}

public extension DependencyValues {
    var appThrottleClient: AppThrottleClient {
        get { self[AppThrottleClient.self] }
        set { self[AppThrottleClient.self] = newValue }
    }
}
