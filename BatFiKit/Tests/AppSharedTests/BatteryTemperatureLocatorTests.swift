//
//  BatteryTemperatureLocatorTests.swift
//  BatFi
//
//  The macOS 27 "no temperature row at all" bug: the reading did not disappear, it
//  moved. Through macOS 26 AppleSmartBattery published it at the top level; on 27 that
//  node publishes neither key, and the value sits in the `BatteryData` of the child
//  AppleSmartBatteryPack node. Both shapes below are copied from real machines.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct BatteryTemperatureLocatorTests {
    /// macOS 26.6, measured on the dev Mac: both keys at the top level, ~4 °C apart.
    private let macOS26Node: [String: Any] = [
        "CycleCount": 278,
        "VirtualTemperature": 3519,
        "Temperature": 3084,
        "BatteryData": ["CurrentCapacity": 70, "Temperature": 3084],
    ]

    /// macOS 27.0 (26A5406e), measured: no temperature on the matched node, and its
    /// BatteryData trimmed to capacity fields only.
    private let macOS27Node: [String: Any] = [
        "CycleCount": 278,
        "BatteryData": [
            "AbsoluteCapacity": 0,
            "CurrentCapacity": 70,
            "DesignCapacity": 6249,
            "FullChargeCapacity": 5060,
        ],
    ]

    /// macOS 27.0, the child AppleSmartBatteryPack node.
    private let macOS27PackNode: [String: Any] = [
        "BatteryData": [
            "CurrentCapacity": 70,
            "Temperature": 3259,
            "VirtualTemperature": 3259,
        ]
    ]

    @Test func readsTheTopLevelPropertyOnMacOS26() {
        #expect(BatteryTemperatureLocator.temperatureRaw(in: macOS26Node) == 3519)
    }

    /// `VirtualTemperature` reads hotter than `Temperature` where both exist, so it stays
    /// first: the fallback must never trip the hot-battery cutout *earlier* than today.
    @Test func prefersVirtualTemperatureOverTemperature() {
        let node: [String: Any] = ["VirtualTemperature": 3519, "Temperature": 3084]
        #expect(BatteryTemperatureLocator.temperatureRaw(in: node) == 3519)
    }

    @Test func fallsBackToTemperatureWhenVirtualTemperatureIsAbsent() {
        #expect(BatteryTemperatureLocator.temperatureRaw(in: ["Temperature": 3084]) == 3084)
    }

    /// The regression itself: the macOS 27 matched node yields nothing, which is what
    /// sends the caller looking at the child nodes.
    @Test func findsNothingOnTheMacOS27MatchedNode() {
        #expect(BatteryTemperatureLocator.temperatureRaw(in: macOS27Node) == nil)
    }

    @Test func readsTheNestedPropertyOnTheMacOS27PackNode() {
        #expect(BatteryTemperatureLocator.temperatureRaw(in: macOS27PackNode) == 3259)
    }

    /// A node that publishes neither key anywhere must stay nil rather than invent a
    /// reading — a wrong temperature is worse than a missing one, because the
    /// hot-battery cutout acts on it.
    @Test func aNodeWithNoTemperatureAnywhereIsNil() {
        let unrelated: [String: Any] = ["CycleCount": 278, "BatteryData": ["CurrentCapacity": 70]]
        #expect(BatteryTemperatureLocator.temperatureRaw(in: unrelated) == nil)
        #expect(BatteryTemperatureLocator.temperatureRaw(in: [:]) == nil)
    }

    /// IOKit hands back CFNumbers of whatever width the firmware used; the reading is
    /// hundredths of a degree and must survive as a Double either way.
    @Test func acceptsIntegerAndFloatingPointReadings() {
        #expect(BatteryTemperatureLocator.temperatureRaw(in: ["Temperature": Int32(3259)]) == 3259)
        #expect(BatteryTemperatureLocator.temperatureRaw(in: ["Temperature": 3259.5]) == 3259.5)
    }

    /// The top level wins over `BatteryData` on the same node, so macOS 26 keeps reading
    /// exactly the value it read before this lookup existed.
    @Test func theTopLevelWinsOverTheNestedDictionary() {
        let node: [String: Any] = ["Temperature": 3084, "BatteryData": ["Temperature": 9999]]
        #expect(BatteryTemperatureLocator.temperatureRaw(in: node) == 3084)
    }

    /// The accessor overload is what the IOKit caller uses: it must read `BatteryData`
    /// only when both top-level keys miss, since that dictionary is large and this runs
    /// on every power-source change.
    @Test func theAccessorReadsBatteryDataOnlyAsALastResort() {
        var requested: [String] = []
        _ = BatteryTemperatureLocator.temperatureRaw { key in
            requested.append(key)
            return key == "VirtualTemperature" ? 3519 : nil
        }
        #expect(requested == ["VirtualTemperature"])

        requested.removeAll()
        _ = BatteryTemperatureLocator.temperatureRaw { key in
            requested.append(key)
            return nil
        }
        #expect(requested == ["VirtualTemperature", "Temperature", "BatteryData"])
    }
}
