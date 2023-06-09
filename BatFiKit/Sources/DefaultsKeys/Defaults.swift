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
    public static let chargeLimit = Key<Int>("chargeLimit", default: 80)
    public static let manageCharging = Key<Bool>("manageCharging", default: true)
    public static let temperatureSwitch = Key<Bool>("temperatureSwitch", default: true)
    public static let disableCharging = Key<Bool>("disableCharging", default: false)
    public static let forceCharge = Key<Bool>("forceCharge", default: false)
    public static let allowDischargingFullBattery = Key<Bool>("allowDischargingFullBattery", default: false)
    public static let disableSleep = Key<Bool>("disableSleep", default: false)
    public static let onboardingIsDone = Key<Bool>("onboardingIsDone", default: false)
    public static let monochromeStatusIcon = Key<Bool>("monochromeStatusIcon", default: true)
    public static let showBatteryPercentageInStatusIcon = Key<Bool>("showBatteryPercentageInStatusIcon", default: true)
    public static let showDebugMenu = Key<Bool>("showDebugMenu", default: showDebugMenuByDefault)


    // notifications
    public static let showChargingStausChanged = Key<Bool>("showChargingStausChanged", default: true)
    public static let showOptimizedBatteryCharging = Key<Bool>("showOptimizedBatteryCharging", default: true)

}
