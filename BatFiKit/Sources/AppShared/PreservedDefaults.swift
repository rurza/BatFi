//
//  PreservedDefaults.swift
//  BatFi
//
//  What "Reset settings" carries across the reset.
//

import Foundation

/// The stored values of the defaults that a settings reset must not lose.
///
/// Not everything in `UserDefaults` is a setting. Some keys record system state BatFi changed
/// and must undo — `systemSleepDisabledByBatFi` was the first — and a reset that empties the
/// suite forgets them, leaving BatFi unable to undo what it did. So the reset takes one of
/// these first, empties the suite, and restores it.
///
/// Only values actually *stored* are kept, read from the persistent domain rather than with
/// `object(forKey:)`. The Defaults package registers every key's default value, so a plain
/// read answers for a key that was never written, and writing that answer back would turn
/// "never set" into a stored value.
public struct PreservedDefaults {
    private let storedValues: [String: Any]

    /// - Parameters:
    ///   - keys: the names of the keys to carry across.
    ///   - domainName: the persistent domain `defaults` writes to — the bundle identifier for
    ///     `UserDefaults.standard`, the suite name for a suite.
    public init(keys: [String], domainName: String, in defaults: UserDefaults) {
        let stored = defaults.persistentDomain(forName: domainName) ?? [:]
        var values: [String: Any] = [:]
        for key in keys {
            values[key] = stored[key]
        }
        storedValues = values
    }

    public func restore(into defaults: UserDefaults) {
        for (key, value) in storedValues {
            defaults.set(value, forKey: key)
        }
    }
}
