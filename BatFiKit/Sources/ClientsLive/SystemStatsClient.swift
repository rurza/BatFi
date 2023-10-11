import AppKit
import AppShared
import Clients
import Defaults
import Dependencies
import Shared

extension SystemStatsClient: DependencyKey {
    public static var liveValue: SystemStatsClient {
        @Sendable func topCoalitionInfo() -> TopCoalitionInfo? {
            guard let systemstats_get_top_coalitions = Private.systemstats_get_top_coalitions else {
                return nil
            }
            let threshold = Defaults[.highEnergyImpactProcessesThreshold]
            let duration = Defaults[.highEnergyImpactProcessesDuration] * 60
            let capacity = Defaults[.highEnergyImpactProcessesCapacity]
            guard
                let rawTopCoalitions = systemstats_get_top_coalitions(duration, 10000).takeUnretainedValue() as? [String: Any],
                let bundleIdentifiers = rawTopCoalitions["bundle_identifiers"] as? [String],
                let energyImpacts = rawTopCoalitions["energy_impacts"] as? [Double],
                bundleIdentifiers.count == energyImpacts.count
            else {
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
        
        @Sendable func batteryChargeGraphInfo() -> BatteryChargeGraphInfo? {
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
            topCoalitionInfoChanges: {
                AsyncStream { continuation in
                    let task = Task {
                        var prevInfo: TopCoalitionInfo?
                        while !Task.isCancelled {
                            if let info = topCoalitionInfo(), info != prevInfo {
                                continuation.yield(info)
                                prevInfo = info
                            }
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                    continuation.onTermination = { _ in
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
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                    continuation.onTermination = { _ in
                        task.cancel()
                    }
                }
            }
        )
        return client
    }
}
