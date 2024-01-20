//
//  Defaults.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import Defaults
import Foundation

#if DEBUG
private let showDebugMenuByDefault = true
#else
private let showDebugMenuByDefault = false
#endif

public extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: true)
    static let forceCharge = Key<Bool>("forceCharge", default: false)
    static let onboardingIsDone = Key<Bool>("onboardingIsDone", default: false)

    // Charging
    static let manageCharging = Key<Bool>("manageCharging", default: true)
    static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    static let allowDischargingFullBattery = Key<Bool>("allowDischargingFullBattery", default: false)

    // Menu bar
    static let showBatteryPercentageInStatusIcon = Key<Bool>("showBatteryPercentageInStatusIcon", default: true)
    static let monochromeStatusIcon = Key<Bool>("monochromeStatusIcon", default: true)
    static let showChart = Key<Bool>("showChart", default: false)
    static let showPowerDiagram = Key<Bool>("showPowerDiagram", default: false)
    static let showHighEnergyImpactProcesses = Key<Bool>("showHighEnergyImpactProcesses", default: false)

    // Advanced
    static let downloadBetaVersion = Key<Bool>("downloadBetaVersion", default: false)
    static let showDebugMenu = Key<Bool>("showDebugMenu", default: showDebugMenuByDefault)
    static let disableSleep = Key<Bool>("disableSleep", default: false)
    static let showGreenLightMagSafeWhenInhibiting = Key<Bool>("showGreenLightMagSafeWhenInhibiting", default: false)
    static let turnOnInhibitingChargingWhenGoingToSleep = Key<Bool>("turnOnInhibitingChargingWhenGoingToSleep", default: false)
    static let temperatureSwitch = Key<Bool>("temperatureSwitch", default: true)
    static let turnOnSystemChargeLimitingWhenGoingToSleep = Key<Bool>("turnOnSystemChargeLimitingWhenGoingToSleep", default: false)

    static let highEnergyImpactProcessesThreshold = Key<Int>("highEnergyImpactProcessesThreshold", default: 500)
    static let highEnergyImpactProcessesDuration = Key<TimeInterval>("highEnergyImpactProcessesDuration", default: 180)
    static let highEnergyImpactProcessesCapacity = Key<Int>("highEnergyImpactProcessesCapacity", default: 5)

    // notifications
    static let showChargingStausChanged = Key<Bool>("showChargingStausChanged", default: true)
    static let showOptimizedBatteryCharging = Key<Bool>("showOptimizedBatteryCharging", default: true)
    static let blinkMagSafeWhenDischarging = Key<Bool>("blinkMagSafeWhenDischarging", default: false)
    static let showBatteryLowNotification = Key<Bool>("showBatteryLowNotification", default: false)

    // feature flags
    static let enableHighEnergyImpactProcesses = Key<Bool>("enableHighEnergyImpactProcesses", default: false)
    static let enablePowerDiagram = Key<Bool>("enablePowerDiagram", default: false)
}
