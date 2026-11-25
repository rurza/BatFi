//
//  FrontmostGrace.swift
//  BatFi
//
//  Which app is in front, and which left it too recently to be slowed down again.
//

import Foundation

/// Keeps track of the app in front for "Slow down on battery", and of the grace an app gets
/// after leaving it.
///
/// The two directions are handled differently on purpose. An app coming to the front is
/// given back at once: the user is about to use it. An app leaving the front is slowed again
/// only once its grace has run out, which absorbs Cmd-Tab cycling and the flap of BatFi's own
/// status item — clicking it brings BatFi to the front, and closing the menu hands the front
/// back.
///
/// Each grace carries a generation, so that the timer of a grace the app has since cut short
/// — by coming back — or restarted — by leaving again — ends nothing.
public struct FrontmostGrace: Equatable, Sendable {
    /// How long an app that left the front is spared.
    public static let duration: Duration = .seconds(5)

    /// One app's grace, as its timer has to hand it back when it runs out.
    public struct Grace: Hashable, Sendable {
        public let bundleID: String
        public let generation: UInt64
    }

    /// What a change of the app in front calls for.
    public struct Change: Equatable, Sendable {
        /// Something new came to the front: evaluate now, from a fresh snapshot, so that a
        /// slowed app the user turns to is given back without waiting.
        public var evaluateNow: Bool
        /// The app that left the front: evaluate again once this grace ends.
        public var graceStarted: Grace?

        public init(evaluateNow: Bool, graceStarted: Grace?) {
            self.evaluateNow = evaluateNow
            self.graceStarted = graceStarted
        }
    }

    public private(set) var frontmostPID: Int32?
    public private(set) var frontmostBundleID: String?
    /// The generation of each running grace, by bundle identifier.
    private var graces: [String: UInt64] = [:]
    private var lastGeneration: UInt64 = 0

    public init() {}

    /// The apps that left the front too recently to be slowed down again.
    public var recentlyActiveBundleIDs: Set<String> { Set(graces.keys) }

    /// Records the app now in front.
    public mutating func frontmostChanged(pid: Int32?, bundleID: String?) -> Change {
        guard pid != frontmostPID || bundleID != frontmostBundleID else {
            return Change(evaluateNow: false, graceStarted: nil)
        }
        let leaving = frontmostBundleID
        frontmostPID = pid
        frontmostBundleID = bundleID

        // Back before its grace ran out: it is in front now, which spares it on its own.
        if let bundleID { graces[bundleID] = nil }

        var started: Grace?
        // Another instance of the same app taking the front is not the app leaving it.
        if let leaving, leaving != bundleID {
            lastGeneration += 1
            graces[leaving] = lastGeneration
            started = Grace(bundleID: leaving, generation: lastGeneration)
        }
        return Change(evaluateNow: true, graceStarted: started)
    }

    /// Waits out a grace on `clock`.
    ///
    /// - Returns: whether it ran out; false if the waiting task was cancelled first.
    public static func runOut(on clock: any Clock<Duration>) async -> Bool {
        (try? await clock.sleep(for: duration)) != nil
    }

    /// Ends a grace whose timer ran out.
    ///
    /// - Returns: whether it was still running, in which case the app may be slowed again
    ///   and is worth evaluating.
    public mutating func graceEnded(_ grace: Grace) -> Bool {
        guard graces[grace.bundleID] == grace.generation else { return false }
        graces[grace.bundleID] = nil
        return true
    }
}
