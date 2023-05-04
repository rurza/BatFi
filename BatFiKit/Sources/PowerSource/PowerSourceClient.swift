//
//  PowerSourceClient.swift
//  
//
//  Created by Adam on 28/04/2023.
//

import Foundation

public struct PowerSourceClient {
    public var powerSourceChanges: () -> AsyncStream<PowerState>
    public var currentPowerSourceState: () -> PowerState
}
