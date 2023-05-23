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

public struct ObserveDefaultsClient: TestDependencyKey {
    public var observeChargeLimit: () -> AsyncStream<Int>
    public var observeManageCharging: () -> AsyncStream<Bool>
    public var observeAllowDischargingFullBattery: () -> AsyncStream<Bool>
    public var observePreventSleeping: () -> AsyncStream<Bool>
    public var observeForceCharging: () -> AsyncStream<Bool>
    public var observeTemperature: () -> AsyncStream<Bool>

    public init(
        observeChargeLimit: @escaping () -> AsyncStream<Int>,
        observeManageCharging: @escaping () -> AsyncStream<Bool>,
        observeAllowDischargingFullBattery: @escaping () -> AsyncStream<Bool>,
        observePreventSleeping: @escaping () -> AsyncStream<Bool>,
        observeForceCharging: @escaping () -> AsyncStream<Bool>,
        observeTemperature: @escaping () -> AsyncStream<Bool>
    ) {
        self.observeChargeLimit = observeChargeLimit
        self.observeManageCharging = observeManageCharging
        self.observeAllowDischargingFullBattery = observeAllowDischargingFullBattery
        self.observePreventSleeping = observePreventSleeping
        self.observeForceCharging = observeForceCharging
        self.observeTemperature = observeTemperature
    }

    public static var testValue: ObserveDefaultsClient = unimplemented()
}

public struct SetDefaultsClient: TestDependencyKey {
    public var setChargeLimit: (_ limit: Int) -> Void
    public var setManageCharging: (_ manage: Bool) -> Void
    public var setPreventSleep: (_ prevent: Bool) -> Void
    public var setAllowDischarging: (_ force: Bool) -> Void
    public var setForceCharge: (_ force: Bool) -> Void

    public init(
        setChargeLimit: @escaping (Int) -> Void,
        setManageCharging: @escaping (Bool) -> Void,
        setPreventSleep: @escaping (Bool) -> Void,
        setAllowDischarging: @escaping (Bool) -> Void,
        setForceCharge: @escaping (Bool) -> Void
    ) {
        self.setChargeLimit = setChargeLimit
        self.setManageCharging = setManageCharging
        self.setPreventSleep = setPreventSleep
        self.setAllowDischarging = setAllowDischarging
        self.setForceCharge = setForceCharge
    }

    public static var testValue: SetDefaultsClient = unimplemented()
}

public struct GetDefaultsClient: TestDependencyKey {
    public var chargeLimit: () -> Int
    public var manageCharging: () -> Bool
    public var preventSleep: () -> Bool
    public var allowDischarging: () -> Bool
    public var forceCharge: () -> Bool
    public var turnOffChargingHotBattery: () -> Bool

    public init(
        chargeLimit: @escaping () -> Int,
        manageCharging: @escaping () -> Bool,
        preventSleep: @escaping () -> Bool,
        allowDischarging: @escaping () -> Bool,
        forceCharge: @escaping () -> Bool,
        turnOffChargingHotBattery: @escaping () -> Bool
    ) {
        self.chargeLimit = chargeLimit
        self.manageCharging = manageCharging
        self.preventSleep = preventSleep
        self.allowDischarging = allowDischarging
        self.forceCharge = forceCharge
        self.turnOffChargingHotBattery = turnOffChargingHotBattery
    }

    public static var testValue: GetDefaultsClient = unimplemented()
}

extension DependencyValues {
    public var observeDefaultsClient: ObserveDefaultsClient {
        get { self[ObserveDefaultsClient.self] }
        set { self[ObserveDefaultsClient.self] = newValue }
    }

    public var setDefaultsClient: SetDefaultsClient {
        get { self[SetDefaultsClient.self] }
        set { self[SetDefaultsClient.self] = newValue }
    }

    public var getDefaultsClient: GetDefaultsClient {
        get { self[GetDefaultsClient.self] }
        set { self[GetDefaultsClient.self] = newValue }
    }
}
