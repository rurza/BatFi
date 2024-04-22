//
//  AppChargingStateClient.swift
//
//
//  Created by Adam on 16/05/2023.
//

import AppShared
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
public struct AppChargingStateClient {
    public var updateLidOpenedStatus: @Sendable (_ opened: Bool) async -> Void
    public var lidOpened: @Sendable () async -> Bool?
    public var appChargingModeDidChage: @Sendable () -> AsyncStream<AppChargingMode> = { AsyncStream { _ in } }
    public var currentAppChargingMode: @Sendable () async -> AppChargingMode = { .init(mode: .initial, userTempOverride: nil, chargerConnected: false) }
    public var setAppChargingMode: @Sendable (AppChargingMode) async -> Void
    public var userTempOverrideDidChange: @Sendable () -> AsyncStream<UserTempChargingMode?> = { AsyncStream { _ in } }
    public var currentUserTempOverrideMode: @Sendable () async -> UserTempChargingMode?
    public var updateChargingMode: @Sendable (ChargingMode) async -> Void
    public var setTempOverride: @Sendable (UserTempChargingMode?) async -> Void
    public var setChargerConnected: @Sendable (Bool) async -> Void
}

extension AppChargingStateClient: TestDependencyKey {
    public static var testValue: AppChargingStateClient = .init()
}

public extension DependencyValues {
    var appChargingState: AppChargingStateClient {
        get { self[AppChargingStateClient.self] }
        set { self[AppChargingStateClient.self] = newValue }
    }
}
