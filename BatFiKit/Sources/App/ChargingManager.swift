//
//  ChargingManager.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import Charging
import Dependencies
import Foundation

final class ChargingManager {
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient

    init() {
        
    }
}
