//
//  HighEnergyUsageView+Model.swift
//
//
//  Created by Adam on 24/10/2023.
//

import AsyncAlgorithms
import AppShared
import Defaults
import DefaultsKeys
import Foundation
import Clients
import Combine
import Dependencies

extension HighEnergyUsageView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.highEnergyImpactClient) private var highEnergyImpactClient
        @Dependency(\.defaults)               private var defaults

        @Published private(set) var topCoalitionInfo: TopCoalitionInfo?
        private var changesTask: Task<Void, Never>?
        private var defaultsTask: Task<Void, Never>?

        func startObserving() {
            defaultsTask = Task {
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
            topCoalitionInfo = nil
        }

        private func startObservingHighEnergyUsage(
            capacity: Int,
            threshold: Int,
            duration: TimeInterval
        ) {
            changesTask?.cancel()
            changesTask = Task {
                for await info in highEnergyImpactClient.topCoalitionInfoChanges(threshold, duration, capacity) {
                    self.topCoalitionInfo = info
                }
            }
        }
    }
}
