//
//  HighEnergyUsageView+Model.swift
//
//
//  Created by Adam on 24/10/2023.
//

import AppShared
import Clients
import Combine
import Dependencies

extension HighEnergyUsageView {
    @MainActor
    final class Model: ObservableObject {
        @Dependency(\.highEnergyImpactClient) private var highEnergyImpactClient
        @Published private(set) var topCoalitionInfo: TopCoalitionInfo?
        private var changesTask: Task<Void, Never>?

        func startObserving() {
            changesTask = Task {
                for await info in highEnergyImpactClient.topCoalitionInfoChanges() {
                    self.topCoalitionInfo = info
                }
            }
        }

        func cancelObserving() {
            changesTask?.cancel()
            topCoalitionInfo = nil
        }
    }
}
