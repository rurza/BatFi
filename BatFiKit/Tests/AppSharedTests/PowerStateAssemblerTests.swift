//
//  PowerStateAssemblerTests.swift
//  BatFi
//
//  The macOS 27 "stuck initializing" bug: one missing IORegistry value used to
//  throw and take down the entire power state stream. Only genuinely required
//  fields may fail; everything else degrades to nil.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct PowerStateAssemblerTests {
    /// Every required field present, every optional field absent.
    private var minimal: PowerSourceReadings {
        PowerSourceReadings(
            batteryLevel: 80,
            isCharging: false,
            powerSource: "Battery Power",
            chargerConnected: false
        )
    }

    @Test func assemblesWithOnlyRequiredFields() throws {
        let state = try PowerStateAssembler.assemble(minimal)
        #expect(state.batteryLevel == 80)
        #expect(state.isCharging == false)
        #expect(state.powerSource == "Battery Power")
        #expect(state.chargerConnected == false)
        #expect(state.timeLeft == nil)
        #expect(state.timeToCharge == nil)
        #expect(state.batteryCycleCount == nil)
        #expect(state.batteryTemperature == nil)
        #expect(state.batteryHealth == nil)
        #expect(state.optimizedBatteryChargingEngaged == nil)
    }

    @Test func populatesOptionalFieldsWhenPresent() throws {
        var readings = minimal
        readings.timeLeft = 49
        readings.timeToCharge = -1
        readings.cycleCount = 272
        readings.temperatureRaw = 3500
        readings.batteryHealth = 85
        readings.optimizedBatteryChargingEngaged = true

        let state = try PowerStateAssembler.assemble(readings)
        #expect(state.timeLeft == 49)
        #expect(state.timeToCharge == -1)
        #expect(state.batteryCycleCount == 272)
        #expect(state.batteryHealth == 85)
        #expect(state.optimizedBatteryChargingEngaged == true)
    }

    /// AppleSmartBattery reports hundredths of a degree: 3500 -> 35.0 C.
    @Test func convertsRawTemperatureToCelsius() throws {
        var readings = minimal
        readings.temperatureRaw = 3500
        let state = try PowerStateAssembler.assemble(readings)
        #expect(state.batteryTemperature == 35.0)
    }

    /// The regression guard: no single optional value may prevent assembly.
    @Test func anyOptionalMissingIndividuallyStillAssembles() throws {
        var full = minimal
        full.timeLeft = 49
        full.timeToCharge = 0
        full.cycleCount = 272
        full.temperatureRaw = 3500
        full.batteryHealth = 85
        full.optimizedBatteryChargingEngaged = false

        var withoutTime = full;        withoutTime.timeLeft = nil; withoutTime.timeToCharge = nil
        var withoutCycles = full;      withoutCycles.cycleCount = nil
        var withoutTemperature = full; withoutTemperature.temperatureRaw = nil
        var withoutHealth = full;      withoutHealth.batteryHealth = nil
        var withoutOBC = full;         withoutOBC.optimizedBatteryChargingEngaged = nil

        for readings in [withoutTime, withoutCycles, withoutTemperature, withoutHealth, withoutOBC] {
            #expect(throws: Never.self) { try PowerStateAssembler.assemble(readings) }
        }
    }

    @Test func missingRequiredFieldNamesTheField() {
        var noLevel = minimal;   noLevel.batteryLevel = nil
        var noCharging = minimal; noCharging.isCharging = nil
        var noSource = minimal;  noSource.powerSource = nil
        var noCharger = minimal; noCharger.chargerConnected = nil

        let expectations: [(PowerSourceReadings, PowerSourceField)] = [
            (noLevel, .batteryLevel),
            (noCharging, .isCharging),
            (noSource, .powerSource),
            (noCharger, .chargerConnected),
        ]

        for (readings, expectedField) in expectations {
            #expect(throws: PowerSourceAssemblyError(missingField: expectedField)) {
                try PowerStateAssembler.assemble(readings)
            }
        }
    }

    @Test func errorDescriptionNamesTheIOKitKey() {
        let error = PowerSourceAssemblyError(missingField: .chargerConnected)
        #expect(error.description.contains("ExternalConnected"))
    }
}
