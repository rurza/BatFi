//
//  AppChargingMode.swift
//  
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public enum AppChargingMode: String, Equatable {
    case charging
    case inhibit
    case forceDischarge
    case forceCharge
    case disabled
    case chargerNotConnected
}
