//
//  ChartsViewModel.swift
//
//
//  Created by Adam on 03/09/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation
import IdentifiedCollections
import os

final class ChartsViewModel: ObservableObject {
    @Dependency(\.persistence) private var persistence
    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar
    @MainActor
    @Published var powerStatePoints: IdentifiedArrayOf<PowerStatePoint> = []
    private lazy var logger = Logger(category: "ChartsView.Model")

    var fromDate: Date {
        let components = calendar.dateComponents([.minute, .second], from: toDate)
        return calendar.date(
            byAdding: DateComponents(
                hour: -12,
                minute: -components.minute!,
                second: -components.second!
            ),
            to: toDate
        )!
    }

    var toDate: Date { date.now }

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
        do {
            let results = try await persistence.fetchPowerStatePoint(fromDate, toDate)
            if let first = results.first, date.now.timeIntervalSince(first.timestamp) <= 60 * 60 {
                powerStatePoints = []
                return
            }
            let reduceDuplicatedDates = results.reduce(
                into: [PowerStatePoint](),
                { array, powerStatePoint in
                    guard let lastElement = array.last else {
                        array.append(powerStatePoint)
                        return
                    }
                    guard lastElement.timestamp != powerStatePoint.timestamp else {
                        return
                    }
                    array.append(powerStatePoint)
                }
            )
            powerStatePoints = IdentifiedArray(uniqueElements: reduceDuplicatedDates)
        } catch {
            logger.error("error when fetching power state: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    func offsetDateFor(_ point: PowerStatePoint) -> Date {
        guard let index = powerStatePoints.index(id: point.id) else {
            // this timestamp can be used in upper bound
            // so let's add some small time interval to mitigate crash
            return point.timestamp.addingTimeInterval(0.1)
        }

        if index < powerStatePoints.count - 1 {
            let nextPointIndex = powerStatePoints.index(after: index)
            let nextPoint = powerStatePoints[nextPointIndex]
            if nextPoint.appChargingMode == point.appChargingMode {
                return nextPoint.timestamp
            }
        } else {
            return date.now
        }
        return point.timestamp.addingTimeInterval(0.1)
    }
}
