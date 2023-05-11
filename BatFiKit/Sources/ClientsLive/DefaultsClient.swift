//
//  DefaultsClient.swift
//  
//
//  Created by Adam on 11/05/2023.
//

import Clients
import Defaults
import Dependencies
import Foundation
import os
import Settings
import Shared

extension DefaultsClient: DependencyKey {
    public static let liveValue: DefaultsClient = {
        let logger = Logger(category: "🔧")
        let client = DefaultsClient(
            observeChargeLimit: {
                AsyncStream(Defaults.updates(.chargeLimit).map {
                    let value = Int($0)
                    logger.debug("ChargeLimit did change: \(value)")
                    return value
                })
            },
            observeManageCharging: {
                AsyncStream(Defaults.updates(.manageCharging).map {
                    logger.debug("ManageCharging did change: \($0)")
                    return $0
                })
            },
            observeAllowDischargingFullBattery: {
                AsyncStream(Defaults.updates(.allowDischargingFullBattery).map {
                    logger.debug("AllowDischargingFullBattery did change: \($0)")
                    return $0
                })
            },
            observePreventSleeping: {
                AsyncStream(Defaults.updates(.disableSleep).map {
                    logger.debug("Disable sleep did change: \($0)")
                    return $0
                })
            }
        )
        return client
    }()
}
