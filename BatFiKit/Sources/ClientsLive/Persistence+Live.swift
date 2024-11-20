//
//  Persistence.swift
//
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import Clients
import CoreData
import Dependencies
import Foundation
import os
import Persistence
import Shared

extension Persistence: DependencyKey {
    public static let liveValue: Persistence = {
        let logger = Logger(category: "Persistence")

        @Dependency(\.date) var date

        func fetchLastFullChargeDate(context: NSManagedObjectContext) throws -> Date? {
            let fetchRequest = PowerStateModel.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PowerStateModel.timestamp, ascending: false)]
            fetchRequest.predicate = NSPredicate(format: "%K >= %@", #keyPath(PowerStateModel.batteryLevel), 100 as NSNumber)
            fetchRequest.fetchLimit = 1
            let results = try context.fetch(fetchRequest)
            return results.first?.timestamp
        }

        func fetchLastDischargeDate(context: NSManagedObjectContext) throws -> Date? {
            let fetchRequest = PowerStateModel.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PowerStateModel.timestamp, ascending: false)]
            fetchRequest.predicate = NSPredicate(format: "%K <= %@", #keyPath(PowerStateModel.batteryLevel), 1 as NSNumber)
            fetchRequest.fetchLimit = 1
            let results = try context.fetch(fetchRequest)
            return results.first?.timestamp
        }

        return Persistence(
            savePowerState: { state, chargingMode in
                try await persistenceContainer.performBackgroundTask { context in
                    logger.debug("Will save a new power state: \(state), mode: \(chargingMode)")
                    _ = PowerStateModel(powerState: state, appChargingMode: chargingMode, context: context)
                    do {
                        try context.save()
                    } catch {
                        logger.error("Error when saving the new power state. \(error.localizedDescription, privacy: .public)")
                        throw error
                    }
                }
            },
            fetchPowerStatePoint: { fromDate, toDate in
                try await persistenceContainer.performBackgroundTask { context in
                    let fetchRequest = PowerStateModel.fetchRequest()
                    let fromPredicate = NSPredicate(format: "%K > %@", #keyPath(PowerStateModel.timestamp), fromDate as NSDate)
                    let toPredicate = NSPredicate(format: "%K =< %@", #keyPath(PowerStateModel.timestamp), toDate as NSDate)
                    let modePredicate = NSPredicate(format: "%K != %@", #keyPath(PowerStateModel.appMode), ChargingMode.initial.rawValue)
                    fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [fromPredicate, toPredicate, modePredicate])
                    fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PowerStateModel.timestamp, ascending: true)]

                    let fetchFirstItemRequest = PowerStateModel.fetchRequest()
                    fetchFirstItemRequest.predicate = NSPredicate(format: "%K <= %@", #keyPath(PowerStateModel.timestamp), fromDate as NSDate)
                    fetchFirstItemRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PowerStateModel.timestamp, ascending: false)]
                    fetchFirstItemRequest.fetchLimit = 1

                    let results = try context.fetch(fetchRequest)
                    let firstItem: PowerStatePoint? = try context.fetch(fetchFirstItemRequest)
                        .first
                        .flatMap { $0.point }
                    if let firstItem {
                        return [firstItem] + results.map(\.point)
                    } else {
                        return results.map(\.point)
                    }
                }
            },
            observePowerStatePoints: {
                AsyncStream { continuation in
                    let delegate = FetchedResultsControllerDelegate {
                        continuation.yield()
                    }
                    let fetchRequest = PowerStateModel.fetchRequest()
                    fetchRequest.fetchLimit = 1
                    fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PowerStateModel.timestamp, ascending: false)]

                    let controller = NSFetchedResultsController(
                        fetchRequest: fetchRequest,
                        managedObjectContext: persistenceContainer.viewContext,
                        sectionNameKeyPath: nil,
                        cacheName: nil
                    )
                    controller.delegate = delegate
                    do {
                        try controller.performFetch()
                    } catch {
                        logger.error("Failed to observe power state. \(error.localizedDescription, privacy: .public)")
                    }

                    continuation.onTermination = { _ in
                        _ = delegate
                        _ = controller
                    }
                }
            },
            fetchLastDischargeDate: {
                try await persistenceContainer.performBackgroundTask { context in
                    try fetchLastDischargeDate(context: context)
                }
            },
            fetchLastFullChargeDate: {
                try await persistenceContainer.performBackgroundTask { context in
                    try fetchLastFullChargeDate(context: context)
                }
            },
            fullChargeAndDischargeWasInLast30Days: {
                try await persistenceContainer.performBackgroundTask { context in
                    let referenceDate = date.now.addingTimeInterval(-30 * 24 * 60 * 60)
                    let oldestDataPointRequest = PowerStateModel.fetchRequest()
                    oldestDataPointRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PowerStateModel.timestamp, ascending: true)]
                    oldestDataPointRequest.fetchLimit = 1
                    guard let oldestDataPoint = try context.fetch(oldestDataPointRequest).first, oldestDataPoint.timestamp <= referenceDate else {
                        return nil
                    }
                    let lastFullChageDate = try fetchLastFullChargeDate(context: context)
                    let lastDischargeDate = try fetchLastDischargeDate(context: context)
                    let wasFullyChargedIn30Days = lastFullChageDate != nil && lastFullChageDate! >= referenceDate
                    let wasDischargedIn30Days = lastDischargeDate != nil && lastDischargeDate! >= referenceDate
                    return (wasFullyChargedIn30Days, wasDischargedIn30Days)
                }
            }
        )
    }()
}

private class FetchedResultsControllerDelegate: NSObject, NSFetchedResultsControllerDelegate {
    private var handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        handler()
    }
}
