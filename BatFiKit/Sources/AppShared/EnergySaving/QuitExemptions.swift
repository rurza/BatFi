//
//  QuitExemptions.swift
//  BatFi
//
//  Which apps the high-energy list has just asked to quit, and so are left alone.
//

import Foundation

/// Keeps track of the apps asked to quit from the high-energy list, which "Slow down on
/// battery" gives back and leaves alone for `duration`.
///
/// A slowed app can be too starved to answer a quit — one slowed "Always", while other work
/// keeps the Mac busy, can get no CPU at all — and too starved to show the dialog a quit may
/// bring up, such as one about unsaved changes. Once the exemption ends, an app still running
/// is slowed again by the usual rules.
///
/// Each exemption carries a generation, so that the timer of one the app has since been
/// asked again for — which starts it over — ends nothing.
public struct QuitExemptions: Equatable, Sendable {
    /// How long an app asked to quit is left alone: longer than the list's own watch of the
    /// quit, so that the app is not slowed again while the list still waits for it.
    public static let duration: Duration = .seconds(15)

    /// One app's exemption, as its timer has to hand it back when it runs out.
    public struct Exemption: Hashable, Sendable {
        public let bundleID: String
        public let generation: UInt64
    }

    /// The generation of each running exemption, by bundle identifier.
    private var exemptions: [String: UInt64] = [:]
    private var lastGeneration: UInt64 = 0

    public init() {}

    /// The apps asked to quit that are left alone now.
    public var bundleIDs: Set<String> { Set(exemptions.keys) }

    /// Leaves the app alone from now on, for `duration` — starting over if it already was.
    public mutating func exempt(_ bundleID: String) -> Exemption {
        lastGeneration += 1
        exemptions[bundleID] = lastGeneration
        return Exemption(bundleID: bundleID, generation: lastGeneration)
    }

    /// Waits out an exemption on `clock`.
    ///
    /// - Returns: whether it ran out; false if the waiting task was cancelled first.
    public static func runOut(on clock: any Clock<Duration>) async -> Bool {
        (try? await clock.sleep(for: duration)) != nil
    }

    /// Ends an exemption whose timer ran out.
    ///
    /// - Returns: whether it was still running, in which case the usual rules are back for
    ///   the app and a pass is worth running.
    public mutating func ended(_ exemption: Exemption) -> Bool {
        guard exemptions[exemption.bundleID] == exemption.generation else { return false }
        exemptions[exemption.bundleID] = nil
        return true
    }
}
