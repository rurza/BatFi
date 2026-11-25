//
//  BatteryTemperatureLocator.swift
//
//
//  Where the battery temperature lives in one IORegistry node's properties.
//
//  Kept free of IOKit so both firmware shapes can be tested directly. This owns the key
//  lookup at a single node; walking to a neighbouring node is the caller's job, because
//  only the caller can enumerate the registry.
//

import Foundation

public enum BatteryTemperatureLocator {
    /// In priority order. Both are published where either is, and `VirtualTemperature`
    /// reads the hotter of the two — measured about 4 °C apart on macOS 26 — so it stays
    /// first: a fallback that read lower would trip the hot-battery cutout *later* than
    /// the value BatFi shipped with.
    public static let keys = ["VirtualTemperature", "Temperature"]

    /// The dictionary the reading moved into on macOS 27.
    public static let nestedDictionaryKey = "BatteryData"

    /// The raw reading — hundredths of a degree Celsius — in one node's properties, or nil
    /// if this node does not carry it.
    ///
    /// Through macOS 26 the `AppleSmartBattery` node published both keys at the top level
    /// (measured 3519 and 3084 on the dev Mac). On macOS 27.0, build 26A5406e, that node
    /// publishes neither, and its `BatteryData` is trimmed to capacity fields; the reading
    /// is on the child `AppleSmartBatteryPack` node, inside *its* `BatteryData` (3259 for
    /// both keys, the two having converged). Hence: top level first, so macOS 26 reads
    /// exactly what it read before, then the nested dictionary, then — up to the caller —
    /// the child nodes.
    ///
    /// - Parameter value: reads one property of the node. Called lazily, so a firmware
    ///   that still publishes the value at the top level never pays for `BatteryData`,
    ///   which is a large dictionary fetched on every power-source change.
    public static func temperatureRaw(_ value: (String) -> Any?) -> Double? {
        if let raw = firstReading(value) { return raw }
        guard let nested = value(nestedDictionaryKey) as? [String: Any] else { return nil }
        return firstReading { nested[$0] }
    }

    /// Dictionary convenience for a node whose properties have already been fetched.
    public static func temperatureRaw(in properties: [String: Any]) -> Double? {
        temperatureRaw { properties[$0] }
    }

    /// `NSNumber` rather than `Double`: IOKit hands back CFNumbers of whatever width the
    /// firmware chose, and a direct `as? Double` fails on the integer ones.
    private static func firstReading(_ value: (String) -> Any?) -> Double? {
        for key in keys {
            if let number = value(key) as? NSNumber { return number.doubleValue }
        }
        return nil
    }
}
