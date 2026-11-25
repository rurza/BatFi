//
//  ThrottleEligibility.swift
//  BatFi
//
//  Which apps in the high-energy list BatFi offers to slow down on battery, or to quit.
//

import Foundation

/// Whether an app in the high-energy list gets "Slow down on battery" and Quit.
///
/// `canOfferActions` decides whether BatFi acts on the app at all; Quit then needs it to be
/// running (`canQuit`), and the tortoise needs it to show in the Dock (`canSlowDown`).
///
/// Both actions are for the user's own apps. The parts of macOS that draw the desktop, the
/// Dock and the menu bar are not offered: slowing them makes the whole Mac feel broken, and
/// quitting them just restarts them. Apple's ordinary apps — Safari, Music, Mail, which live
/// under `/System/Applications` — stay eligible, since they are exactly the kind people want
/// to slow down.
public enum ThrottleEligibility {
    /// Parts of macOS, wherever they happen to be installed.
    public static let deniedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.Spotlight",
    ]

    /// Where macOS keeps its own components rather than apps.
    public static let protectedLocations = ["/System/Library/", "/Library/Apple/", "/usr/"]

    /// What the high-energy list shows when macOS withholds an app's name.
    static let redactedBundleIDs: Set<String> = ["<private>", "REDACTED"]

    /// - Parameters:
    ///   - bundleID: the bundle identifier the high-energy list reported.
    ///   - bundleURL: where the running app's bundle is, or nil where it could not be found —
    ///     no running app, or one without a bundle.
    ///   - ownBundleIDs: BatFi's own bundle identifiers, release and beta.
    public static func canOfferActions(bundleID: String?, bundleURL: URL?, ownBundleIDs: Set<String>) -> Bool {
        guard let bundleID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !bundleID.isEmpty,
              !redactedBundleIDs.contains(bundleID),
              let bundleURL
        else { return false }

        // Bundle identifiers compare case-insensitively, as Launch Services compares them.
        let id = bundleID.lowercased()
        if deniedBundleIDs.contains(where: { $0.lowercased() == id }) { return false }
        if ownBundleIDs.contains(where: { $0.lowercased() == id }) { return false }

        // The default APFS volume is case-insensitive, so `/system/library/` is the same place.
        let path = bundleURL.standardizedFileURL.path(percentEncoded: false).lowercased()
        return !protectedLocations.contains { path.hasPrefix($0.lowercased()) }
    }

    // MARK: - Quit and the tortoise

    /// Whether the row offers Quit: an eligible app that is running, whatever its activation
    /// policy — a menu bar app such as Dropbox quits like any other.
    ///
    /// - Parameter eligible: what `canOfferActions` says about the app.
    public static func canQuit(eligible: Bool, isRunning: Bool) -> Bool {
        eligible && isRunning
    }

    /// Whether the row offers the tortoise: an eligible app that shows in the Dock.
    ///
    /// BatFi slows down only apps with a Dock icon, since only those come to the front and
    /// are given back when the user turns to them. A menu bar app slowed "in the background"
    /// never comes to the front, so it would stay slowed, and freeze while other work loads
    /// the Mac. A running app is judged by what it does now; one that is not running, by what
    /// its bundle declares.
    ///
    /// - Parameters:
    ///   - eligible: what `canOfferActions` says about the app.
    ///   - isRegular: whether a running instance has a Dock icon (`.regular` activation
    ///     policy). Ignored while the app is not running.
    ///   - declaresNoDockIcon: `declaresNoDockIcon(_:)` of the app's bundle. Ignored while
    ///     the app is running: some apps that declare no Dock icon show one while a window
    ///     is open.
    public static func canSlowDown(eligible: Bool, isRunning: Bool, isRegular: Bool, declaresNoDockIcon: Bool) -> Bool {
        guard eligible else { return false }
        return isRunning ? isRegular : !declaresNoDockIcon
    }

    /// Whether a bundle's Info.plist says the app has no Dock icon: `LSUIElement` (a menu bar
    /// or agent app) or `LSBackgroundOnly`, set to true.
    ///
    /// Apps ship the value as a boolean, a number or a string ("1", "YES", "true"), so all
    /// three are read.
    public static func declaresNoDockIcon(_ infoDictionary: [String: Any]?) -> Bool {
        guard let infoDictionary else { return false }
        return ["LSUIElement", "LSBackgroundOnly"].contains { key in
            switch infoDictionary[key] {
            case let value as Bool: value
            case let value as Int: value != 0
            case let value as String: ["1", "yes", "true"].contains(value.lowercased())
            default: false
            }
        }
    }

    /// Why "Add App…" won't add an app.
    public enum AddRefusal: Equatable, Sendable {
        /// A part of macOS or BatFi itself, or a bundle BatFi can't identify.
        case notEligible
        /// An app without a Dock icon; see `canSlowDown`.
        case noDockIcon
    }

    /// Why "Add App…" won't add the app it was given, or nil where it adds it.
    ///
    /// - Parameters:
    ///   - eligible: what `canOfferActions` says about the app.
    ///   - declaresNoDockIcon: `declaresNoDockIcon(_:)` of the app's bundle.
    public static func addRefusal(eligible: Bool, declaresNoDockIcon: Bool) -> AddRefusal? {
        if !eligible { return .notEligible }
        if declaresNoDockIcon { return .noDockIcon }
        return nil
    }
}
