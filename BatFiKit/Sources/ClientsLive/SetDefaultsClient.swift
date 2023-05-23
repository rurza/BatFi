//
//  SetDefaultsClient.swift
//  
//
//  Created by Adam on 15/05/2023.
//

import Clients
import Defaults
import DefaultsKeys
import Dependencies
import os
import Shared

extension SetDefaultsClient: DependencyKey {
    static public let liveValue: SetDefaultsClient = {
        let logger = Logger(category: "🫸🔧")
        let client = SetDefaultsClient(
            setChargeLimit: { limit in
                Defaults[.chargeLimit] = Double(limit)
            },
            setManageCharging: { manage in
                Defaults[.manageCharging] = manage
            },
            setPreventSleep: { prevent in
                Defaults[.disableSleep] = prevent
            },
            setAllowDischarging: { discharge in
                Defaults[.allowDischargingFullBattery] = discharge
            },
            setForceCharge: { charge in
                Defaults[.forceCharge] = charge
            }
        )
        return client
    }()
}
