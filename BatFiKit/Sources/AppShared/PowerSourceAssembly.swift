//
//  PowerSourceAssembly.swift
//
//
//  Pure conversion from IOKit readings to PowerState.
//
//  Kept free of IOKit so it can be tested directly, and so the required/optional
//  distinction lives in one reviewable place. Only fields that charging decisions
//  depend on are required; display values degrade to nil.
//

import Foundation

/// A power-source value that must be present. Raw values are the IOKit key names,
/// so a log line names exactly which key went missing on a new firmware.
public enum PowerSourceField: String, Sendable, CaseIterable {
    case batteryLevel = "Current Capacity"
    case isCharging = "Is Charging"
    case powerSource = "Power Source State"
    case chargerConnected = "ExternalConnected"
}

public struct PowerSourceAssemblyError: Error, Equatable, CustomStringConvertible {
    public let missingField: PowerSourceField

    public init(missingField: PowerSourceField) {
        self.missingField = missingField
    }

    public var description: String {
        "Required power source field missing: \(missingField.rawValue)"
    }
}

/// Raw values read from IOPS and AppleSmartBattery, before validation.
public struct PowerSourceReadings: Sendable {
    // Required
    public var batteryLevel: Int?
    public var isCharging: Bool?
    public var powerSource: String?
    public var chargerConnected: Bool?

    // Optional — display only
    public var timeLeft: Int?
    public var timeToCharge: Int?
    public var cycleCount: Int?
    /// AppleSmartBattery `VirtualTemperature`, in hundredths of a degree Celsius.
    public var temperatureRaw: Double?
    public var batteryHealth: Int?
    public var optimizedBatteryChargingEngaged: Bool?

    public init(
        batteryLevel: Int? = nil,
        isCharging: Bool? = nil,
        powerSource: String? = nil,
        chargerConnected: Bool? = nil,
        timeLeft: Int? = nil,
        timeToCharge: Int? = nil,
        cycleCount: Int? = nil,
        temperatureRaw: Double? = nil,
        batteryHealth: Int? = nil,
        optimizedBatteryChargingEngaged: Bool? = nil
    ) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.chargerConnected = chargerConnected
        self.timeLeft = timeLeft
        self.timeToCharge = timeToCharge
        self.cycleCount = cycleCount
        self.temperatureRaw = temperatureRaw
        self.batteryHealth = batteryHealth
        self.optimizedBatteryChargingEngaged = optimizedBatteryChargingEngaged
    }
}

public enum PowerStateAssembler {
    public static func assemble(_ readings: PowerSourceReadings) throws -> PowerState {
        guard let batteryLevel = readings.batteryLevel else {
            throw PowerSourceAssemblyError(missingField: .batteryLevel)
        }
        guard let isCharging = readings.isCharging else {
            throw PowerSourceAssemblyError(missingField: .isCharging)
        }
        guard let powerSource = readings.powerSource else {
            throw PowerSourceAssemblyError(missingField: .powerSource)
        }

        // ExternalConnected is the precise signal and takes priority: while the adapter is
        // isolated to force-discharge, the charger is still connected even though the power
        // source reads battery. Fall back to the power source only when the IORegistry value
        // is unavailable, so a renamed or missing property degrades instead of taking down
        // the whole power state stream.
        let resolvedChargerConnected = readings.chargerConnected ?? (powerSource == "AC Power")

        return PowerState(
            batteryLevel: batteryLevel,
            isCharging: isCharging,
            powerSource: powerSource,
            timeLeft: readings.timeLeft,
            timeToCharge: readings.timeToCharge,
            batteryCycleCount: readings.cycleCount,
            batteryHealth: readings.batteryHealth,
            batteryTemperature: readings.temperatureRaw.map { $0 / 100 },
            chargerConnected: resolvedChargerConnected,
            optimizedBatteryChargingEngaged: readings.optimizedBatteryChargingEngaged
        )
    }
}
