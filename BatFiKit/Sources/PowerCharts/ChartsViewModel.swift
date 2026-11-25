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

@MainActor
final class ChartsViewModel: ObservableObject {
    @Dependency(\.persistence) private var persistence
    @Dependency(\.date) private var date
    @Dependency(\.calendar) private var calendar
    @Published var powerStatePoints: IdentifiedArrayOf<PowerStatePoint> = []
    private lazy var logger = Logger(category: "ChartsView.Model")
    private var observingTask: Task<Void, Never>?

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
        #if DEBUG
            print("🟢 ChartsViewModel init")
        #endif
        setUpObserving()
    }

    private func setUpObserving() {
        observingTask = Task { [weak self] in
            await self?.fetchPowerStatePoints()
            guard let persistence = self?.persistence else { return }
            for await _ in await persistence.powerStateDidChange() {
                guard let self else { break }
                await self.fetchPowerStatePoints()
            }
        }
    }

    deinit {
        observingTask?.cancel()
        #if DEBUG
            print("🔴 ChartsViewModel deinit")
        #endif
    }

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

    /// The x-axis extent of `point`'s marks. Hands back a range rather than an end date
    /// so that no caller can plot a reversed one — see `ChartMarkInterval`.
    func markRange(for point: PowerStatePoint) -> Range<Date> {
        ChartMarkInterval.range(start: point.timestamp, naturalEnd: naturalEnd(for: point))
    }

    /// Where `point`'s sample stops being the current one, or `nil` if that is unknowable.
    ///
    /// Note the newest sample answers `date.now`, read here at render time while
    /// `point.timestamp` was read at fetch time — so this can legitimately land *before*
    /// the start. `ChartMarkInterval` is what absorbs that.
    private func naturalEnd(for point: PowerStatePoint) -> Date? {
        guard let index = powerStatePoints.index(id: point.id) else { return nil }
        guard index < powerStatePoints.count - 1 else { return date.now }
        let nextPoint = powerStatePoints[powerStatePoints.index(after: index)]
        return nextPoint.appChargingMode == point.appChargingMode ? nextPoint.timestamp : nil
    }
}
