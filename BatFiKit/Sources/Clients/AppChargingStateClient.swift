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
    /// Whether macOS is holding charge back on its own right now, and in which of the two
    /// ways it does that.
    ///
    /// Deliberately **not** folded into `updateChargingMode`. The mode is what BatFi last
    /// told the hardware and is only ever advanced by an applier that succeeded; this is a
    /// fact about the machine that keeps changing while the mode sits still — `.inhibit`
    /// covers the drain, the hold that follows it, and the hold below the limit. Setting
    /// these together with the mode would
    /// put this behind `ChargingManager.shouldApply`, which skips the applier entirely once
    /// the mode is already in force, and the label would then latch on whatever was true
    /// the last time a command actually went out.
    /// - Parameters:
    ///   - draining: macOS is running the battery *down* to the limit.
    ///   - holdingBelowLimit: macOS is holding charge on a battery already *below* the limit,
    ///     having closed the charge session and not re-opened it.
    ///
    /// Both facts in one call because they are two answers to the same question — why charge
    /// is being held when BatFi is not holding it — and are mutually exclusive on any real
    /// reading. Every caller knows both at once, and one setter is one place to keep them
    /// consistent: set separately, a path that cleared one and forgot the other would latch
    /// the stale sentence, which is the exact failure these flags exist to prevent.
    public var setSystemChargeHold: @Sendable (_ draining: Bool, _ holdingBelowLimit: Bool, _ chargingPastLimit: Bool) async -> Void
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
