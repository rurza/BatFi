//
//  ChartsViewModel.swift
//  
//
//  Created by Adam on 03/09/2023.
//

import AppShared
import Clients
import Foundation
import Dependencies
import os

extension ChartsView {
    final class Model: ObservableObject {
        @Dependency(\.persistence) private var persistence
        @Dependency(\.date) private var date
        @Dependency(\.calendar) private var calendar
        @MainActor
        @Published var powerStatePoints: [PowerStatePoint] = []
        private lazy var logger = Logger(category: "📈🌁")

        init() {
            Task {
                await fetchPowerStatePoints()
                for await _ in await persistence.powerStateDidChange() {
                    await fetchPowerStatePoints()
                }
            }
        }

        @MainActor
        private func fetchPowerStatePoints() async {
            let toDate = date.now
            guard let fromDate = calendar.date(byAdding: DateComponents(hour: -12), to: toDate) else {
                logger.error("Can't create a from date from the toDate: \(toDate, privacy: .public)")
                return
            }
            do {
                let results = try await persistence.fetchPowerStatePoint(fromDate, toDate)
                self.powerStatePoints = results
            } catch {
                logger.error("error when fetching power state: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
