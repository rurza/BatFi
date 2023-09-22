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

extension Defaults.Keys {
    public static let launchAtLogin = Key<Bool>("launchAtLogin", default: true)
    public static let forceCharge = Key<Bool>("forceCharge", default: false)
    public static let onboardingIsDone = Key<Bool>("onboardingIsDone", default: false)

    // Charging
    public static let manageCharging = Key<Bool>("manageCharging", default: true)
    public static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    public static let allowDischargingFullBattery = Key<Bool>("allowDischargingFullBattery", default: false)

    // Menu bar
    public static let showBatteryPercentageInStatusIcon = Key<Bool>("showBatteryPercentageInStatusIcon", default: true)
    public static let monochromeStatusIcon = Key<Bool>("monochromeStatusIcon", default: true)
    public static let showChart = Key<Bool>("showChart", default: true)
    public static let showPowerDiagram = Key<Bool>("showPowerDiagram", default: false)
    public static let showHighEnergyImpactProcesses = Key<Bool>("showHighEnergyImpactProcesses", default: false)
    public static let highEnergyImpactProcessesThreshold = Key<Int>("highEnergyImpactProcessesThreshold", default: 500)
    public static let highEnergyImpactProcessesDuration = Key<Int>("highEnergyImpactProcessesDuration", default: 2)
    public static let highEnergyImpactProcessesCapacity = Key<Int>("highEnergyImpactProcessesCapacity", default: 5)

    // Advanced
    public static let downloadBetaVersion = Key<Bool>("downloadBetaVersion", default: false)
    public static let showDebugMenu = Key<Bool>("showDebugMenu", default: showDebugMenuByDefault)
    public static let disableSleep = Key<Bool>("disableSleep", default: false)
    public static let showGreenLightMagSafeWhenInhibiting = Key<Bool>("showGreenLightMagSafeWhenInhibiting", default: false)
    public static let turnOnInhibitingChargingWhenGoingToSleep = Key<Bool>("turnOnInhibitingChargingWhenGoingToSleep", default: false)
    public static let temperatureSwitch = Key<Bool>("temperatureSwitch", default: true)


    // notifications
    public static let showChargingStausChanged = Key<Bool>("showChargingStausChanged", default: true)
    public static let showOptimizedBatteryCharging = Key<Bool>("showOptimizedBatteryCharging", default: true)
    public static let blinkMagSafeWhenDischarging = Key<Bool>("blinkMagSafeWhenDischarging", default: false)
    public static let showBatteryLowNotification = Key<Bool>("showBatteryLowNotification", default: false)
}
