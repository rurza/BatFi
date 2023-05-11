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

public struct DefaultsClient: TestDependencyKey {
    public var observeChargeLimit: () -> AsyncStream<Int>
    public var observeManageCharging: () -> AsyncStream<Bool>
    public var observeAllowDischargingFullBattery: () -> AsyncStream<Bool>
    public var observePreventSleeping: () -> AsyncStream<Bool>

    public init(
        observeChargeLimit: @escaping () -> AsyncStream<Int>,
        observeManageCharging: @escaping () -> AsyncStream<Bool>,
        observeAllowDischargingFullBattery: @escaping () -> AsyncStream<Bool>,
        observePreventSleeping: @escaping () -> AsyncStream<Bool>
    ) {
        self.observeChargeLimit = observeChargeLimit
        self.observeManageCharging = observeManageCharging
        self.observeAllowDischargingFullBattery = observeAllowDischargingFullBattery
        self.observePreventSleeping = observePreventSleeping
    }

    public static var testValue: DefaultsClient = unimplemented()
}

extension DependencyValues {
    public var defaultsClient: DefaultsClient {
        get { self[DefaultsClient.self] }
        set { self[DefaultsClient.self] = newValue }
    }
}
