//
//  HighEnergyUsageView+Model.swift
//
//
//  Created by Adam on 24/10/2023.
//

import AppShared
import AsyncAlgorithms
import Clients
import Combine
import Defaults
import DefaultsKeys
import Dependencies
import Foundation

@MainActor
final class HighEnergyUsageViewModel: ObservableObject {
    @Dependency(\.energyStatsClient) private var energyStatsClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.appThrottleClient) private var appThrottleClient

    @Published private(set) var topCoalitionInfo: TopCoalitionInfo?
    /// The apps slowed down on battery, as stored — whether a row shows a tortoise at all,
    /// and whether its button slows the app down or stops.
    @Published private(set) var slowedApps: [String: SlowDownMode] = [:]
    /// Whether the Mac is on its battery, and whether BatFi is slowing each app in the list
    /// down at this moment, and if not, why — which button a row offers, whether its
    /// tortoise is in the accent colour or grey, and what the tooltips say. Nil until the
    /// throttle manager's first pass.
    @Published private(set) var slowDownReport: SlowDownReport?
    /// The master switch. While it is off, the rows offer no slow-down button: it would do
    /// nothing.
    @Published private(set) var slowDownEnabled = true
    private var changesTask: Task<Void, Never>?
    private var defaultsTask: Task<Void, Never>?
    private var slowedAppsTask: Task<Void, Never>?

    init() {
        #if DEBUG
            print("🟢 HighEnergyUsageViewModel init")
        #endif
    }

    func startObserving() {
        defaultsTask?.cancel()
        defaultsTask = Task { [weak self] in
            guard let defaults = self?.defaults else { return }
            for await (capacity, threshold, duration) in combineLatest(
                defaults.observe(.highEnergyImpactProcessesCapacity),
                defaults.observe(.highEnergyImpactProcessesThreshold),
                defaults.observe(.highEnergyImpactProcessesDuration)
            ) {
                guard let self else { break }
                self.startObservingHighEnergyUsage(capacity: capacity, threshold: threshold, duration: duration)
            }
        }
        slowedAppsTask?.cancel()
        slowedAppsTask = Task { [weak self] in
            guard let defaults = self?.defaults, let appThrottleClient = self?.appThrottleClient else { return }
            for await (isEnabled, apps, report) in combineLatest(
                defaults.observe(.slowDownAppsOnBattery),
                defaults.observe(.slowedOnBatteryApps),
                // Published by the throttle manager after every pass.
                appThrottleClient.slowDownReportChanges()
            ) {
                guard let self else { break }
                self.slowDownEnabled = isEnabled
                self.slowedApps = apps
                self.slowDownReport = report
            }
        }
    }

    func cancelObserving() {
        defaultsTask?.cancel()
        changesTask?.cancel()
        slowedAppsTask?.cancel()
    }

    /// Slows the app down on battery from now on, or stops. BatFi's throttle manager follows
    /// the stored list by itself.
    func toggleSlowDown(_ bundleID: String) {
        // Read afresh rather than from `slowedApps`: the Energy pane edits the same list.
        let apps = SlowedApps.toggling(bundleID, in: defaults.value(.slowedOnBatteryApps))
        defaults.setValue(.slowedOnBatteryApps, value: apps)
        slowedApps = apps
    }

    private func startObservingHighEnergyUsage(
        capacity: Int,
        threshold: Int,
        duration: TimeInterval
    ) {
        changesTask?.cancel()
        changesTask = Task { @MainActor [weak self] in
            guard let energyStatsClient = self?.energyStatsClient else { return }
            for await info in energyStatsClient.topCoalitionInfoChanges(threshold, duration, capacity) {
                guard let self else { break }
                self.topCoalitionInfo = info
            }
        }
    }

    deinit {
        changesTask?.cancel()
        defaultsTask?.cancel()
        slowedAppsTask?.cancel()
        #if DEBUG
            print("🔴 HighEnergyUsageViewModel deinit")
        #endif
    }
}
