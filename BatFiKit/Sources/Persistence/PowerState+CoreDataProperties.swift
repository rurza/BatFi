//
//  PowerState+CoreDataProperties.swift
//  BatFi
//
//  Created by Adam on 12/07/2023.
//
//

import Foundation
import CoreData

extension PowerStateModel {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PowerStateModel> {
        return NSFetchRequest<PowerStateModel>(entityName: "PowerState")
    }

    @NSManaged public var batteryLevel: Int16
    @NSManaged public var appMode: String
    @NSManaged public var isCharging: Bool
    @NSManaged public var timestamp: Date
    @NSManaged public var batteryTemperature: Double
    @NSManaged public var chargerConnected: Bool
}
