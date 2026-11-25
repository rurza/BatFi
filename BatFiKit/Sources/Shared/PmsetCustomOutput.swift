//
//  PmsetCustomOutput.swift
//  BatFi
//

import Foundation

/// One of the per-power-source profiles `pmset` keeps: what `pmset -b` and `pmset -c` write.
public enum PowerSourceProfile: Hashable, Sendable {
    case battery
    case ac
}

/// Reads a setting per power source out of `pmset -g custom` output.
///
/// `pmset -g` prints only the values currently in use, so it cannot say whether Low Power
/// Mode is on for the battery, for the power adapter, or both — and System Settings'
/// choices (Never, Always, Only on Battery, Only on Power Adapter) are exactly those pairs.
/// `pmset -g custom` prints each profile under its own header:
///
///     Battery Power:
///      powermode            0
///      …
///     AC Power:
///      powermode            0
///      …
///
/// `PmsetOutput` cannot read this: it stops at the first match, in whichever section that
/// falls, and cannot say which one it was.
public enum PmsetCustomOutput {
    /// The value recorded against `key` in each profile that has it as a number.
    ///
    /// Sections other than `Battery Power:` and `AC Power:` — `UPS Power:` on a Mac with a
    /// UPS attached, or anything a later macOS adds — are skipped, as is anything before
    /// the first header. `key` must be the first whitespace-separated token of its line and
    /// match it whole, never as a prefix or substring; its value is the token after it. Tabs
    /// and spaces both separate. Anchoring to the start of the line keeps the same word
    /// inside another setting's value from being read as the setting. The price is that
    /// multi-word names (`Sleep On Power Button`) cannot be read, and none are needed.
    public static func values(forKey key: String, in output: String) -> [PowerSourceProfile: UInt8] {
        var values: [PowerSourceProfile: UInt8] = [:]
        var section: PowerSourceProfile?
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(":") {
                section = profile(forHeader: trimmed)
                continue
            }
            // The first match in a section is its value; pmset never repeats a key within one.
            guard let section, values[section] == nil else { continue }
            let tokens = line.split(whereSeparator: \.isWhitespace)
            guard tokens.first == key[...], tokens.count > 1 else { continue }
            values[section] = UInt8(tokens[1])
        }
        return values
    }

    /// The Low Power Mode setting of each profile, or `nil` where neither key appears in
    /// either profile.
    ///
    /// Macs with High Power Mode publish `powermode` (0 automatic, 1 low power, 2 high
    /// power); the rest publish `lowpowermode` (0 or 1). `powermode` wins as soon as either
    /// section has it, and the two keys are never mixed into one answer: a value is only
    /// ever written back under the key it was read from.
    public static func powerModeBySource(in output: String) -> PowerModeBySource? {
        for usesPowermodeKey in [true, false] {
            let key = PowerModeBySource.pmsetKey(usesPowermodeKey: usesPowermodeKey)
            let found = values(forKey: key, in: output)
            if !found.isEmpty {
                return PowerModeBySource(
                    battery: found[.battery],
                    ac: found[.ac],
                    usesPowermodeKey: usesPowermodeKey
                )
            }
        }
        return nil
    }

    private static func profile(forHeader header: String) -> PowerSourceProfile? {
        switch header {
        case "Battery Power:": .battery
        case "AC Power:": .ac
        default: nil
        }
    }
}
