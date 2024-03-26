//
//  AppChargingMode.swift
//
//
//  Created by Adam on 15/05/2023.
//

import Foundation

public enum AppChargingMode: String, Equatable, Identifiable {
    case initial
    case charging
    case inhibit
    case forceDischarge
    case forceCharge

    public var id: String { rawValue }
}
