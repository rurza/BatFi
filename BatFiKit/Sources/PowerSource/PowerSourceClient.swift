//
//  PowerSourceClient.swift
//  
//
//  Created by Adam on 28/04/2023.
//

import Foundation

public enum PowerSourceError: Error {
    case infoMissing
}

public struct PowerSourceClient {
    public var powerSourceChanges: () -> AsyncStream<PowerState>
    public var currentPowerSourceState: () throws -> PowerState
}
