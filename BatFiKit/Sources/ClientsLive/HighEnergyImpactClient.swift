import AppKit
import AppShared
import Clients
import Dependencies
import os
import Shared

extension HighEnergyImpactClient: DependencyKey {
    public static var liveValue: HighEnergyImpactClient {
        @Sendable func topCoalitionInfo(threshold: Int, duration: TimeInterval, capacity: Int) -> TopCoalitionInfo? {
            guard let systemstats_get_top_coalitions = Private.systemstats_get_top_coalitions else {
                return nil
            }
            guard
                let topCoalitionDictionary = systemstats_get_top_coalitions(Int(duration), 10000).takeUnretainedValue() as? [String: Any],
                let bundleIdentifiers = topCoalitionDictionary["bundle_identifiers"] as? [String],
                let energyImpacts = topCoalitionDictionary["energy_impacts"] as? [Double],
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
        let logger = Logger(category: "🅰️⚡️📊")
        let client = Self(
            topCoalitionInfoChanges: { threshold, duration, capacity in
                AsyncStream { continuation in
                    let task = Task {
                        var prevInfo: TopCoalitionInfo?
                        while !Task.isCancelled {
                            if let info = topCoalitionInfo(threshold: threshold, duration: duration, capacity: capacity),
                                info != prevInfo {
                                logger.debug("New top coalition info: \(info)")
                                continuation.yield(info)
                                prevInfo = info
                            }
                            try await Task.sleep(for: .seconds(3))
                        }
                    }
                    continuation.onTermination = { _ in
                        logger.debug("Task terminated")
                        task.cancel()
                    }
                }
            }
        )
        return client
    }
}

class Private {
    static let systemstats_get_top_coalitions = {
        var systemstats_get_top_coalitionsPointer: UnsafeMutableRawPointer?
        if let handle = dlopen("/usr/lib/libsystemstats.dylib", RTLD_LAZY) {
            systemstats_get_top_coalitionsPointer = dlsym(handle, "systemstats_get_top_coalitions")
            dlclose(handle)
        }
        let systemstats_get_top_coalitions =
        unsafeBitCast(systemstats_get_top_coalitionsPointer, to: (@convention(c) (_ duration: Int, _ count: Int) -> Unmanaged<NSDictionary>)?.self)
        return systemstats_get_top_coalitions
    }()
}
