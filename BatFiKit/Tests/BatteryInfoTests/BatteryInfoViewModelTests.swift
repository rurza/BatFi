//
//  BatteryInfoViewModelTests.swift
//  
//
//  Created by Adam on 04/05/2023.
//

import Dependencies
import XCTest
@testable import BatteryInfo
@testable import PowerSource

@MainActor
final class BatteryInfoViewModelTests: XCTestCase {
    func testPowerState() {
        let powerState = PowerState(
            batteryLevel: 90,
            isCharging: false,
            powerSource: "AC Charger",
            timeLeft: 234,
            timeToCharge: 0,
            batteryCycleCount: 666,
            batteryHealth: "Bad",
            batteryTemperature: 36.6
        )
        let model = withDependencies {
            $0.locale = Locale(identifier: "en_US")
            $0.powerSourceClient.currentPowerSourceState = {
                powerState
            }
        } operation: {
            BatteryInfoView.Model()
        }
        XCTAssertEqual(model.state, powerState)
        let timeLeftDescription = model.timeDescription()
        XCTAssertEqual(timeLeftDescription, "3 hr, 54 min")
        let timeLeftLabel = model.timeLabel()
        XCTAssertEqual(timeLeftLabel, "Time Left")
        let temperature = model.temperatureDescription()
        XCTAssertEqual(temperature, "36.6°C")
    }
}
