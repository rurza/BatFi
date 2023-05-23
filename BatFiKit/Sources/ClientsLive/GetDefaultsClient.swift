//
//  GetDefaultsClient.swift
//  
//
//  Created by Adam on 15/05/2023.
//

import Clients
import Defaults
import DefaultsKeys
import Dependencies

extension GetDefaultsClient: DependencyKey {
    public static let liveValue: GetDefaultsClient = {
        let client = GetDefaultsClient(
            chargeLimit: {
                Int(Defaults[.chargeLimit])
            },
            manageCharging: {
                Defaults[.manageCharging]
            },
            preventSleep: {
                Defaults[.disableSleep]
            },
            allowDischarging: {
                Defaults[.allowDischargingFullBattery]
            },
            forceCharge: {
                Defaults[.forceCharge]
            },
            turnOffChargingHotBattery: {
                Defaults[.temperatureSwitch]
            }
        )
        return client
    }()
}
