//
//  Defaults.swift
//  BatFi
//
//  Created by Adam on 26/04/2023.
//

import Defaults
import Foundation

extension Defaults.Keys {
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let limit = Key<Int>("chargeLimit", default: 80)
    static let disableCharging = Key<Bool>("disableCharging", default: false)
    static let singleDischarging = Key<Bool>("singleDischarging", default: false)
}
