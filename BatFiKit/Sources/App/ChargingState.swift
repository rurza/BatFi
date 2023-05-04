//
//  ChargingStateObject.swift
//  
//
//  Created by Adam on 02/05/2023.
//

import Charging
import Dependencies
import Foundation

@MainActor
final class ChargingStateObject: ObservableObject {
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Published private(set) var powerState: PowerState?

    init() {
        Task {
            for await state in powerSourceClient.powerSourceChanges() {
                self.powerState = state
            }
        }
    }
}
