//
//  Persistence.swift
//  
//
//  Created by Adam on 12/07/2023.
//

import AppShared
import Dependencies
import Foundation

public struct Persistence: TestDependencyKey {
    public var savePowerState: (_ powerState: PowerState, _ mode: AppChargingMode) async throws -> Void

    public init(savePowerState: @escaping (PowerState, AppChargingMode) async throws -> Void) {
        self.savePowerState = savePowerState
    }

    public static var testValue: Persistence = unimplemented()
}

extension DependencyValues {
    public var persistence: Persistence {
        get { self[Persistence.self] }
        set { self[Persistence.self] = newValue }
    }
}
