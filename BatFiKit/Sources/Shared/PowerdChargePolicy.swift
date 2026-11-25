//
//  PowerdChargePolicy.swift
//
//
//  The charge limit powerd is **enforcing**, as opposed to the one BatFi asked for.
//
//  powerd serialises its charge policies into a world-readable plist, so both the helper
//  and the app can read the answer without root and without writing anything. The
//  preference BatFi writes is the input; this is the system's answer. `getMCLLimitWithError:`
//  reports the preference, not enforcement, so it cannot stand in for this.
//

import Foundation

public enum PowerdChargePolicy {
    public static let path = "/Library/Preferences/com.apple.powerd.charging.plist"

    /// The `soclimit` of the policy powerd holds, or nil when it holds none — on battery it
    /// keeps no charge policy at all — or the file cannot be read.
    public static func enforcedLimit() -> Int? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return enforcedLimit(plistData: data)
    }

    /// The same, from the file's contents.
    ///
    /// `policies` is itself a keyed-archiver plist whose `reason` is a UID reference that is
    /// awkward to resolve through PropertyListSerialization. Matching on the presence of
    /// `soclimit` is sufficient: powerd holds a single charge-limit policy at a time.
    public static func enforcedLimit(plistData data: Data) -> Int? {
        guard let top = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let archived = top["policies"] as? Data,
              let archive = try? PropertyListSerialization.propertyList(
                  from: archived, options: [], format: nil) as? [String: Any],
              let objects = archive["$objects"] as? [Any]
        else { return nil }
        for object in objects {
            if let policy = object as? [String: Any], let soclimit = policy["soclimit"] as? Int {
                return soclimit
            }
        }
        return nil
    }
}
