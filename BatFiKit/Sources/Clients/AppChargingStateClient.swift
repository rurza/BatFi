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
public struct AppChargingStateClient: Sendable {
    public var updateLidOpenedStatus: @Sendable (_ opened: Bool) async -> Void
    public var lidOpened: @Sendable () async -> Bool?
    public var appChargingModeDidChage: @Sendable () -> AsyncStream<AppChargingMode> = { AsyncStream { _ in } }
    public var currentAppChargingMode: @Sendable () async -> AppChargingMode = { .init(mode: .initial, userTempOverride: nil, chargerConnected: false) }
    public var setAppChargingMode: @Sendable (AppChargingMode) async -> Void
    public var userTempOverrideDidChange: @Sendable () -> AsyncStream<UserTempChargingMode?> = { AsyncStream { _ in } }
    public var currentUserTempOverrideMode: @Sendable () async -> UserTempChargingMode?
    public var updateChargingMode: @Sendable (ChargingMode) async -> Void
    /// Whether macOS is draining the battery down to the limit on its own right now.
    ///
    /// Deliberately **not** folded into `updateChargingMode`. The mode is what BatFi last
    /// told the hardware and is only ever advanced by an applier that succeeded; this is a
    /// fact about the machine that keeps changing while the mode sits still — `.inhibit`
    /// covers both the drain and the hold that follows it. Setting the two together would
    /// put this behind `ChargingManager.shouldApply`, which skips the applier entirely once
    /// the mode is already in force, and the label would then latch on whatever was true
    /// the last time a command actually went out.
    public var setSystemIsDischargingToLimit: @Sendable (Bool) async -> Void
    public var setTempOverride: @Sendable (UserTempChargingMode?) async -> Void
    public var setChargerConnected: @Sendable (Bool) async -> Void
    /// Base charge limit requested by the automation engine; nil falls back to the user's
    /// configured `chargeLimit`. Lower precedence than a manual temp override.
    public var setAutomationLimit: @Sendable (Int?) async -> Void
    public var currentAutomationLimit: @Sendable () async -> Int?
    public var automationLimitDidChange: @Sendable () -> AsyncStream<Int?> = { AsyncStream { _ in } }
}

extension AppChargingStateClient: TestDependencyKey {
    nonisolated(unsafe) public static var testValue: AppChargingStateClient = .init()
}

public extension DependencyValues {
    var appChargingState: AppChargingStateClient {
        get { self[AppChargingStateClient.self] }
        set { self[AppChargingStateClient.self] = newValue }
    }
}
