//
//  DefaultsClient.swift
//  
//
//  Created by Adam on 10/05/2023.
//

import Defaults
import Dependencies
import Foundation
import os
import Shared

struct DefaultsClient {
    var observeChargeLimit: () -> AsyncStream<Int>
    var observeManageCharging: () -> AsyncStream<Bool>
    var observeAllowDischargingFullBattery: () -> AsyncStream<Bool>
    var observePreventSleeping: () -> AsyncStream<Bool>
}

extension DefaultsClient: DependencyKey {
    static let liveValue: DefaultsClient = {
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

extension DependencyValues {
    var defaultsClient: DefaultsClient {
        get { self[DefaultsClient.self] }
        set { self[DefaultsClient.self] = newValue }
    }
}
