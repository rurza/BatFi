//
//  ChargingManagerTests.swift
//  
//
//  Created by Adam on 10/05/2023.
//

import XCTest
import Dependencies
@testable import AppCore
@testable import PowerSource

@MainActor
final class ChargingManagerTests: XCTestCase {
    func testObserving() {
        let screenshots = AsyncStream<PowerState>.streamWithContinuation()

        let chargingManager = withDependencies { dependencies in
            dependencies.powerSourceClient.powerSourceChanges = {
                AsyncStream { continuation in
                    continuation.yield(
                        PowerState(
                            batteryLevel: 50,
                            isCharging: false,
                            powerSource: "AC",
                            timeLeft: 234,
                            timeToCharge: 0,
                            batteryCycleCount: 666,
                            batteryHealth: "Good",
                            batteryTemperature: 30.23
                        )
                    )
                }
            }
        } operation: {
            ChargingManager()
        }

    }

}
