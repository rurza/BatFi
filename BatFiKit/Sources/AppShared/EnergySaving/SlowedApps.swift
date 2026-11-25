//
//  SlowedApps.swift
//  BatFi
//
//  The edits the menu's tortoise and the Energy pane make to the apps slowed down on
//  battery.
//

import Foundation

/// The list of apps slowed down on battery, by bundle identifier, as the user edits it.
///
/// Each edit takes the list as it is now and returns the new one, so a caller reads the
/// stored list, applies one edit and writes the result back — never a copy it read earlier,
/// since the menu and the Energy pane edit the same list.
public enum SlowedApps {
    /// How a newly added app is slowed: only while it is not the one in use, which is the
    /// mode that cannot make the app the user is working in unresponsive.
    public static let defaultMode: SlowDownMode = .backgroundOnly

    /// The tortoise in the high-energy list: adds the app with the default mode, or takes it
    /// out whatever its mode.
    public static func toggling(_ bundleID: String, in apps: [String: SlowDownMode]) -> [String: SlowDownMode] {
        var apps = apps
        if apps.removeValue(forKey: bundleID) == nil {
            apps[bundleID] = defaultMode
        }
        return apps
    }

    /// "Add App…": adds each app with the default mode. An app already in the list keeps the
    /// mode it has.
    public static func adding(_ bundleIDs: [String], to apps: [String: SlowDownMode]) -> [String: SlowDownMode] {
        var apps = apps
        for bundleID in bundleIDs where apps[bundleID] == nil {
            apps[bundleID] = defaultMode
        }
        return apps
    }

    public static func removing(_ bundleID: String, from apps: [String: SlowDownMode]) -> [String: SlowDownMode] {
        var apps = apps
        apps.removeValue(forKey: bundleID)
        return apps
    }

    /// The mode picker. Changes an app that is in the list and never adds one: the tortoise
    /// may have taken it out while its picker was on screen.
    public static func setting(
        _ mode: SlowDownMode,
        for bundleID: String,
        in apps: [String: SlowDownMode]
    ) -> [String: SlowDownMode] {
        guard apps[bundleID] != nil else { return apps }
        var apps = apps
        apps[bundleID] = mode
        return apps
    }

    /// Whether the warning about `always` applies: some app is slowed while it is in use too.
    public static func usesAlways(_ apps: [String: SlowDownMode]) -> Bool {
        apps.values.contains(.always)
    }
}
