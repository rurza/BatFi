//
//  Defaults.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import Defaults
import Foundation

extension Defaults.Keys {
    public static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    public static let chargeLimit = Key<Double>("chargeLimit", default: 80)
    public static let manageCharging = Key<Bool>("manageCharging", default: true)
    public static let temperatureSwitch = Key<Bool>("temperatureSwitch", default: true)
    public static let disableCharging = Key<Bool>("disableCharging", default: false)
    public static let forceCharge = Key<Bool>("forceCharge", default: false)
    public static let allowDischargingFullBattery = Key<Bool>("allowDischargingFullBattery", default: false)
    public static let disableSleep = Key<Bool>("disableSleep", default: false)

    // notifications
    public static let showChargingStausChanged = Key<Bool>("showChargingStausChanged", default: true)

}
