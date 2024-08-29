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

    @Published private(set) var topCoalitionInfo: TopCoalitionInfo?
    private var changesTask: Task<Void, Never>?
    private var defaultsTask: Task<Void, Never>?

    func startObserving() {
        defaultsTask?.cancel()
        defaultsTask = Task { [weak self] in
            guard let self else { return }
            for await (capacity, threshold, duration) in combineLatest(
                defaults.observe(.highEnergyImpactProcessesCapacity),
                defaults.observe(.highEnergyImpactProcessesThreshold),
                defaults.observe(.highEnergyImpactProcessesDuration)
            ) {
                startObservingHighEnergyUsage(capacity: capacity, threshold: threshold, duration: duration)
            }
        }
    }

    func cancelObserving() {
        defaultsTask?.cancel()
        changesTask?.cancel()
    }

    private func startObservingHighEnergyUsage(
        capacity: Int,
        threshold: Int,
        duration: TimeInterval
    ) {
        changesTask?.cancel()
        changesTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await info in energyStatsClient.topCoalitionInfoChanges(threshold, duration, capacity) {
                print("new coalition: \(info)")
                topCoalitionInfo = info
            }
        }
    }

    deinit {
        changesTask?.cancel()
        defaultsTask?.cancel()
    }
}

