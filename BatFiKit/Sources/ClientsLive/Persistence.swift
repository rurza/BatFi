//
//  Persistence.swift
//
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import CoreData
import Clients
import Dependencies
import Foundation
import os
import Persistence
import Shared

extension Persistence: DependencyKey {
    public static let liveValue: Persistence = {
        let logger = Logger(category: "💾")
        return Persistence(
            savePowerState: { state, mode in
                try await persistenceContainer.performBackgroundTask { context in
                    logger.debug("Will save a new power state: \(state), mode: \(mode.rawValue)")
                    _ = PowerStateModel(powerState: state, appMode: mode, context: context)
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
                    let fromPredicate = NSPredicate(format: "%K >= %@", #keyPath(PowerStateModel.timestamp), fromDate as NSDate)
                    let toPredicate = NSPredicate(format: "%K =< %@", #keyPath(PowerStateModel.timestamp), toDate as NSDate)
                    let modePredicate = NSPredicate(format: "%K != %@", #keyPath(PowerStateModel.appMode), AppChargingMode.initial.rawValue)
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
                        return [firstItem] + results.map { $0.point }
                    } else {
                        return results.map { $0.point }
                    }
                }
            },
            observePowerStatePoints: {
                return AsyncStream { continuation in
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

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        handler()
    }
}

