//
//  PersistenceContainer.swift
//  
//
//  Created by Adam on 12/07/2023.
//

import CoreData
import Foundation
import os
import Shared

public let persistenceContainer: NSPersistentContainer = {
    guard
        let modelURL = Bundle.module.url(forResource:"Model", withExtension: "momd"),
    let model = NSManagedObjectModel(contentsOf: modelURL) else { fatalError()
    }
    let logger = Logger(category: "PERSISTENCE CONTAINER")

    let container = NSPersistentContainer(
        name: "Model",
        managedObjectModel: model
    )
    container.loadPersistentStores { _, error in
        if let error {
            logger.fault("Can not load persistent store! \(error, privacy: .public)")
        }
    }
    return container
}()
