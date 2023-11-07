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
        @Dependency(\.highEnergyImpactClient)   private var highEnergyImpactClient
        @Dependency(\.defaults)                 private var defaults
        @Dependency(\.menuDelegate)             private var menuDelegate

        @Published private(set) var topCoalitionInfo: TopCoalitionInfo?
        private var changesTask: Task<Void, Never>?
        private var defaultsTask: Task<Void, Never>?
        private var menuTask: Task<Void, Never>?

        init() {
            menuTask = Task { [weak self] in
                let stream = await self?.menuDelegate.observeMenu()
                if let stream {
                    for await menuIsVisible in stream {
                        if menuIsVisible {
                            self?.startObserving()
                        } else {
                            self?.cancelObserving()
                        }
                    }
                }
            }
        }

        private func startObserving() {
            defaultsTask?.cancel()
            defaultsTask = Task { [weak self] in
                guard let self else { return }
                for await (capacity, threshold, duration) in combineLatest(
                    self.defaults.observe(.highEnergyImpactProcessesCapacity),
                    self.defaults.observe(.highEnergyImpactProcessesThreshold),
                    self.defaults.observe(.highEnergyImpactProcessesDuration)
                ) {
                    self.startObservingHighEnergyUsage(capacity: capacity, threshold: threshold, duration: duration)
                }
            }
        }

        private func cancelObserving() {
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
                for await info in self.highEnergyImpactClient.topCoalitionInfoChanges(threshold, duration, capacity) {
                    print("new coalition")
                    self.topCoalitionInfo = info
                }
            }
        }

        deinit {
            menuTask?.cancel()
            changesTask?.cancel()
            defaultsTask?.cancel()
        }
    }

}
