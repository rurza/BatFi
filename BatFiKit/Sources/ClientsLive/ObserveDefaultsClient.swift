//
//  ObserveDefaultsClient.swift
//  
//
//  Created by Adam on 11/05/2023.
//

import Clients
import Defaults
import DefaultsKeys
import Dependencies
import Foundation
import os
import Shared

extension ObserveDefaultsClient: DependencyKey {
    public static let liveValue: ObserveDefaultsClient = {
        let logger = Logger(category: "👀🔧")
        func asyncStreamForKey<Value>(_ key: Defaults.Keys.Key<Value>) -> AsyncStream<Value> where Value: CustomStringConvertible {
            AsyncStream(Defaults.updates(key).map {
                logger.debug("\(key.name) did change: \($0.description)")
                return $0
            })
        }

        let client = ObserveDefaultsClient(
            observeChargeLimit: {
                AsyncStream(Defaults.updates(.chargeLimit).map {
                    let value = Int($0)
                    logger.debug("ChargeLimit did change: \(value)")
                    return Int($0)
                })
            },
            observeManageCharging: {
                asyncStreamForKey(.manageCharging)
            },
            observeAllowDischargingFullBattery: {
                asyncStreamForKey(.allowDischargingFullBattery)
            },
            observePreventSleeping: {
                asyncStreamForKey(.disableSleep)
            },
            observeForceCharging: {
                asyncStreamForKey(.forceCharge)
            }
        )

        return client
    }()
}
