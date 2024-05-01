//
//  PowerState+CoreDataProperties.swift
//  BatFi
//
//  Created by Adam on 12/07/2023.
//
//

import CoreData
import Foundation

public extension PowerStateModel {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PowerStateModel> {
        NSFetchRequest<PowerStateModel>(entityName: "PowerState")
    }

    @NSManaged var batteryLevel: Int16
    @NSManaged var appMode: String
    @NSManaged var isCharging: Bool
    @NSManaged var timestamp: Date
    @NSManaged var batteryTemperature: Double
    @NSManaged var chargerConnected: Bool
    // TODO: add a new field that represent user temp charging mode
}
