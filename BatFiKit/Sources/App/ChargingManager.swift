//
//  ChargingManager.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import Charging
import Defaults
import Dependencies
import Foundation
import Settings

final class ChargingManager {
    @Dependency(\.chargingClient) private var chargingClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.screenParametersClient) private var screenParametersClient

    init() {
        Task {
            await setUpObserving()
        }
    }

    private func setUpObserving() async {
        for await _ in screenParametersClient.screenDidChangeParameters() {
            try? await update()
        }
        for await _ in Defaults.updates(.chargeLimit) {
            try? await update()
        }
        for await _ in powerSourceClient.powerSourceChanges() {
            try? await update()
        }
    }

    private func update() async throws {
        let chargingStatus = try await chargingClient.chargingStatus()
        let powerSourceStatus = try powerSourceClient.currentPowerSourceState()
        
    }
}
