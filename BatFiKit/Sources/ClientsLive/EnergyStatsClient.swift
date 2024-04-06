import AppKit
import AppShared
import Clients
import Dependencies
import os
import Shared

extension EnergyStatsClient: DependencyKey {
    public static var liveValue: EnergyStatsClient {
        let energyStatsLogger = Logger(category: "Energy Stats Client")

        @Sendable 
        func topCoalitionInfo(threshold: Int, duration: TimeInterval, capacity: Int) -> TopCoalitionInfo? {
            guard let systemstats_get_top_coalitions = Private.systemstats_get_top_coalitions else {
                energyStatsLogger.notice("No top coalitions info.")
                return nil
            }
            guard
                // https://github.com/rurza/BatFi/issues/24#issuecomment-1899291636
                let topCoalitionDictionary = systemstats_get_top_coalitions(Int(duration + 0), 10000).takeUnretainedValue() as? [String: Any],
                let bundleIdentifiers = topCoalitionDictionary["bundle_identifiers"] as? [String],
                let energyImpacts = topCoalitionDictionary["energy_impacts"] as? [Double],
                bundleIdentifiers.count == energyImpacts.count
            else {
                energyStatsLogger.notice("Top coalition dictionary is empty.")
                return nil
            }
            var topCoalitions = [Coalition]()
            for (index, bundleIdentifier) in bundleIdentifiers.enumerated() {
                guard topCoalitions.count < capacity else {
                    break
                }
                let energyImpact = energyImpacts[index] / Double(duration)
                guard energyImpact >= Double(threshold) else {
                    break
                }
                let bundleIdentifier = bundleIdentifier == "REDACTED" ? "<private>" : bundleIdentifier
                var icon: NSImage?
                var displayName: String?
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                    icon = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
                    if let bundle = Bundle(url: url) {
                        displayName = (
                            bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String ??
                                bundle.infoDictionary?["CFBundleDisplayName"] as? String ??
                                bundle.localizedInfoDictionary?[kCFBundleNameKey as String] as? String ??
                                bundle.infoDictionary?[kCFBundleNameKey as String] as? String
                        )
                    }
                }
                let coalition = Coalition(bundleIdentifier: bundleIdentifier, energyImpact: energyImpact, icon: icon, displayName: displayName)
                topCoalitions.append(coalition)
            }
            return TopCoalitionInfo(topCoalitions: topCoalitions)
        }

        @Sendable 
        func batteryChargeGraphInfo() -> BatteryChargeGraphInfo? {
                    guard
                        let systemstats_get_battery_charge_graph = Private.systemstats_get_battery_charge_graph,
                        let batteryChargeGraph = systemstats_get_battery_charge_graph().takeUnretainedValue() as? [String: Any],
                        let rawBatteryStates = batteryChargeGraph["battery_states"] as? [Bool],
                        let batteryTimes = batteryChargeGraph["battery_times"] as? [UInt],
                        rawBatteryStates.count == batteryTimes.count,
                        let rawChargeLevels = batteryChargeGraph["charge_levels"] as? [UInt8],
                        let chargeTimes = batteryChargeGraph["charge_times"] as? [UInt],
                        rawChargeLevels.count == chargeTimes.count
                    else {
                        return nil
                    }
                    var batteryStates = [BatteryState]()
                    for (index, rawBatteryState) in rawBatteryStates.enumerated() {
                        let batteryTime = batteryTimes[index]
                        let batteryState = BatteryState(state: rawBatteryState, time: batteryTime)
                        batteryStates.append(batteryState)
                    }
                    var chargeLevels = [ChargeLevel]()
                    for (index, rawChargeLevel) in rawChargeLevels.enumerated() {
                        let chargeTime = chargeTimes[index]
                        let chargeLevel = ChargeLevel(level: rawChargeLevel, time: chargeTime)
                        chargeLevels.append(chargeLevel)
                    }
                    return BatteryChargeGraphInfo(batteryStates: batteryStates, chargeLevels: chargeLevels)
                }

        let client = Self(
            topCoalitionInfoChanges: { threshold, duration, capacity in
                AsyncStream { continuation in
                    let task = Task {
                        var prevInfo: TopCoalitionInfo?
                        while !Task.isCancelled {
                            if let info = topCoalitionInfo(threshold: threshold, duration: duration, capacity: capacity),
                               info != prevInfo
                            {
                                energyStatsLogger.notice("New top coalition info: \(info, privacy: .public)")
                                continuation.yield(info)
                                prevInfo = info
                            }
                            try await Task.sleep(for: .seconds(3))
                        }
                    }
                    continuation.onTermination = { _ in
                        energyStatsLogger.debug("Task terminated")
                        task.cancel()
                    }
                }
            },
            batteryChargeGraphInfoChanges: {
                AsyncStream { continuation in
                    let task = Task {
                        var prevInfo: BatteryChargeGraphInfo?
                        while !Task.isCancelled {
                            if let info = batteryChargeGraphInfo(), info != prevInfo {
                                continuation.yield(info)
                                prevInfo = info
                            }
                            try await Task.sleep(for: .seconds(3))
                        }
                    }
                    continuation.onTermination = { _ in
                        energyStatsLogger.debug("Task terminated")
                        task.cancel()
                    }
                }
            }
        )
        return client
    }
}

enum Private {
    public static let (systemstats_get_top_coalitions, systemstats_get_battery_charge_graph) = {
        var systemstats_get_top_coalitionsPointer: UnsafeMutableRawPointer?
        var systemstats_get_battery_charge_graphPointer: UnsafeMutableRawPointer?
        if let handle = dlopen("/usr/lib/libsystemstats.dylib", RTLD_LAZY) {
            systemstats_get_top_coalitionsPointer = dlsym(handle, "systemstats_get_top_coalitions")
            systemstats_get_battery_charge_graphPointer = dlsym(handle, "systemstats_get_battery_charge_graph")
            dlclose(handle)
        }
        let systemstats_get_top_coalitions =
        unsafeBitCast(systemstats_get_top_coalitionsPointer, to: (@convention(c) (_ duration: Int, _ count: Int) -> Unmanaged<NSDictionary>)?.self)
        let systemstats_get_battery_charge_graph =
        unsafeBitCast(systemstats_get_battery_charge_graphPointer, to: (@convention(c) () -> Unmanaged<NSDictionary>)?.self)
        return (systemstats_get_top_coalitions, systemstats_get_battery_charge_graph)
    }()
}
