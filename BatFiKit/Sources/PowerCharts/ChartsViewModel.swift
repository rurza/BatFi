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
import IdentifiedCollections
import os

extension ChartsView {
    final class Model: ObservableObject {
        @Dependency(\.persistence) private var persistence
        @Dependency(\.date) private var date
        @Dependency(\.calendar) private var calendar
        @MainActor
        @Published var powerStatePoints: IdentifiedArrayOf<PowerStatePoint> = []
        private lazy var logger = Logger(category: "📈🌁")

        init() {
            setUpObserving()
        }

        private func setUpObserving() {
            Task {
                await fetchPowerStatePoints()
                for await _ in await persistence.powerStateDidChange() {
                    await fetchPowerStatePoints()
                }
            }
        }

        @MainActor
        func fetchPowerStatePoints() async {
            let toDate = date.now
            let components = calendar.dateComponents([.minute, .second], from: toDate)
            guard let fromDate = calendar.date(
                byAdding: DateComponents(hour: -12, minute: -components.minute!, second: -components.second!),
                to: toDate
            ) else {
                logger.error("Can't create a from date from the toDate: \(toDate, privacy: .public)")
                return
            }
            do {
                let results = try await persistence.fetchPowerStatePoint(fromDate, toDate)
                self.powerStatePoints = IdentifiedArray(uniqueElements: results)
            } catch {
                logger.error("error when fetching power state: \(error.localizedDescription, privacy: .public)")
            }
        }

        @MainActor
        func offsetDateFor(_ point: PowerStatePoint) -> Date {
            let maxDifference: TimeInterval = 600
            guard let index = powerStatePoints.index(id: point.id) else {
                return point.timestamp.advanced(by: maxDifference)
            }

            if index < powerStatePoints.count - 1 {
                let nextPointIndex = powerStatePoints.index(after: index)
                let nextPoint = powerStatePoints[nextPointIndex]
                    return nextPoint.timestamp
            } else {
                return point.timestamp.advanced(by: maxDifference)
            }
        }
    }
}
