//
//  QuitWatch.swift
//  BatFi
//
//  How the high-energy list follows an app it asked to quit: how long it waits, and how
//  long it says what came of it.
//

import Foundation

/// Where a quit asked from the high-energy list has got to, for one app.
public enum QuitProgress: Equatable, Sendable {
    /// Asked, and being watched.
    case quitting
    /// Still running once the watch gave up — most likely showing a dialog, such as one
    /// about unsaved changes. BatFi never forces it.
    case stillOpen
    /// Running, and could not be asked to quit, so nothing is on its way to quitting it.
    case couldNotAsk

    /// Whether this is a hint shown under the app: what came of the quit, rather than the
    /// quit itself.
    public var isHint: Bool { self != .quitting }
}

/// The decisions behind the Quit button's spinner and the hints under it.
public enum QuitWatch {
    /// How long an app asked to quit is watched before the list says it is still open.
    public static let timeout: Duration = .seconds(10)
    /// How often the watch looks.
    public static let interval: Duration = .milliseconds(500)
    /// How long a hint stays under the app. Long enough to be read in a menu opened after
    /// the app's dialog closed it; short enough not to linger into a later, unrelated look.
    public static let hintLifetime: Duration = .seconds(30)

    public enum Verdict: Equatable, Sendable {
        /// Gone: every instance has quit.
        case quit
        /// Still running, and still within the timeout.
        case waiting
        /// Still running once the timeout is up.
        case stillOpen
        /// Still running, and could not be asked: there is nothing to wait for.
        case couldNotAsk
    }

    /// - Parameters:
    ///   - asked: whether every running instance was asked to quit.
    ///   - isRunning: whether any instance of the app is still running.
    ///   - elapsed: how long ago the app was asked to quit.
    public static func verdict(asked: Bool, isRunning: Bool, elapsed: Duration) -> Verdict {
        guard isRunning else { return .quit }
        guard asked else { return .couldNotAsk }
        return elapsed < timeout ? .waiting : .stillOpen
    }

    /// The progress still true once the list has reported the apps again.
    ///
    /// A hint stays only while the list shows its app running: once the app has quit after
    /// all, or dropped out of the list, it would no longer be true. A quit in progress stays
    /// whatever the list says, since the list may have been read before the app was asked;
    /// its watch ends it.
    ///
    /// - Parameter runningBundleIDs: the apps the list shows, and shows running.
    public static func reconciled(
        _ progress: [String: QuitProgress],
        runningBundleIDs: Set<String>
    ) -> [String: QuitProgress] {
        progress.filter { bundleID, progress in
            !progress.isHint || runningBundleIDs.contains(bundleID)
        }
    }
}
