//
//  AppChargingStateClient.swift
//
//
//  Created by Adam on 16/05/2023.
//

import AppShared
import Clients
import Dependencies
import Foundation
import os
import Shared

extension AppChargingStateClient: DependencyKey {
    public static let liveValue: AppChargingStateClient = {
        let logger = Logger(category: "App Charging State")
        let state = AppChargingState.initialState
        logger.debug("Creating a new charging state client")
        let client = AppChargingStateClient(
            updateLidOpenedStatus: { lidIsOpened in
                await state.updateLidOpened(lidIsOpened)
            },
            lidOpened: {
                await state.lidOpened
            },
            appChargingModeDidChage: {
                AsyncStream<AppChargingMode?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.mode)
                        for await note in NotificationCenter.default.notifications(named: ChargingModeDidChangeNotificationName) {
                            let object = note.object as? AppChargingMode
                            continuation.yield(object)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .compactMap { $0 }
                .eraseToStream()
            },
            currentAppChargingMode: {
                await state.mode
            },
            setAppChargingMode: { mode in
                await state.setAppChargingMode(mode)
            },
            userTempOverrideDidChange: {
                AsyncStream<UserTempChargingMode?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.mode.userTempOverride)
                        for await note in NotificationCenter.default.notifications(named: UserTempChargingModeDidChangeNotificationName) {
                            let object = note.object as? UserTempChargingMode
                            continuation.yield(object)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .eraseToStream()
            },
            currentUserTempOverrideMode: {
                await state.mode.userTempOverride
            },
            updateChargingMode: { mode in
                await state.updateMode(mode)
            },
            setSystemChargeHold: { draining, holdingBelowLimit, chargingPastLimit in
                await state.updateSystemChargeHold(
                    draining: draining,
                    holdingBelowLimit: holdingBelowLimit,
                    chargingPastLimit: chargingPastLimit
                )
            },
            setHoldingFullChargeUntilUnplugged: { holding in
                await state.updateHoldingFullChargeUntilUnplugged(holding)
            },
            setSailingHold: { resumeLevel in
                await state.updateSailingHold(resumeLevel)
            },
            updateChargingModeEndingSailingHold: { mode in
                await state.updateMode(mode, endingSailingHold: true)
            },
            setTempOverride: { mode in
                await state.updateOverride(mode)
            },
            endOverride: { ending, end in
                await state.endOverride(ending, with: end)
            },
            setPauseContext: { context in
                await state.updatePauseContext(context)
            },
            currentPauseContext: {
                await state.pauseContext
            },
            pauseContextDidChange: {
                AsyncStream<PauseHoldContext?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.pauseContext)
                        for await note in NotificationCenter.default.notifications(named: PauseContextDidChangeNotificationName) {
                            continuation.yield((note.object as? PauseContextBox)?.context)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .eraseToStream()
            },
            setChargerConnected: { connected in
                await state.updateChargerConnected(connected, awaitingMode: false)
            },
            setChargerConnectedAheadOfMode: { connected in
                await state.updateChargerConnected(connected, awaitingMode: true)
            },
            setAutomationTarget: { target in
                await state.updateAutomationTarget(target)
            },
            currentAutomationTarget: {
                await state.automationTarget
            },
            automationTargetDidChange: {
                AsyncStream<AutomationTarget?> { continuation in
                    let streamTask = Task {
                        await continuation.yield(state.automationTarget)
                        for await note in NotificationCenter.default.notifications(named: AutomationTargetDidChangeNotificationName) {
                            continuation.yield(note.object as? AutomationTarget)
                        }
                    }
                    continuation.onTermination = { _ in
                        streamTask.cancel()
                    }
                }
                .eraseToStream()
            }
        )
        return client
    }()
}

private let ChargingModeDidChangeNotificationName = Notification.Name("ChargingModeDidChangeNotificationName")
private let UserTempChargingModeDidChangeNotificationName = Notification.Name("UserTempChargingModeDidChangeNotificationName")
private let AutomationTargetDidChangeNotificationName = Notification.Name("AutomationTargetDidChangeNotificationName")
private let PauseContextDidChangeNotificationName = Notification.Name("PauseContextDidChangeNotificationName")

/// A struct cannot be a notification's object; this carries one.
private final class PauseContextBox: NSObject, @unchecked Sendable {
    let context: PauseHoldContext
    init(_ context: PauseHoldContext) {
        self.context = context
    }
}

private actor AppChargingState {
    private(set) var mode: AppChargingMode = .init(mode: .initial, userTempOverride: nil, chargerConnected: false)
    private(set) var userTempChargingMode: UserTempChargingMode? = nil
    private(set) var lidOpened: Bool?
    private(set) var automationTarget: AutomationTarget?
    private(set) var pauseContext: PauseHoldContext?

    static let initialState = AppChargingState(lidOpened: nil)

    init(lidOpened: Bool?) {
        self.lidOpened = lidOpened
    }

    func setAppChargingMode(_ mode: AppChargingMode) {
        guard mode != self.mode else { return }
        let oldMode = self.mode
        self.mode = mode
        NotificationCenter.default.post(name: ChargingModeDidChangeNotificationName, object: mode)
        if mode.userTempOverride != oldMode.userTempOverride {
            NotificationCenter.default.post(name: UserTempChargingModeDidChangeNotificationName, object: mode.userTempOverride)
        }
    }

    // `updateSystemChargeHold` is the only writer of those flags,
    // `updateHoldingFullChargeUntilUnplugged` the only writer of the charge-to-full hold, and
    // `updateSailingHold` the only writer of the sailing resume level.
    // Every mutator around them carries across every field it is not itself setting, rather
    // than letting it default back to `false`: none of them is told anything about the drain,
    // the hold, or the charge-to-full hold, and dropping one would relabel a Mac mid-drain as
    // "Inhibiting charging" on the next charger-connection update — which the appliers issue
    // on every pass, i.e. throughout the drain. The charge-to-full hold is worse still: it
    // sits under a mode that keeps alternating between `.charging` and `.inhibit`, so
    // `updateMode` alone would clear it within seconds of it being set.

    /// - Parameter endingSailingHold: clears the sailing resume level in the same publish — an
    ///   applier handing over from a hold, so no state in between reads as the plain inhibit.
    func updateMode(_ newMode: ChargingMode, endingSailingHold: Bool = false) {
        let newAppChargingMode = AppChargingMode(
            mode: newMode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: mode.systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: mode.systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: mode.systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: mode.isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: mode.isAwaitingModeForChargerChange,
            sailingResumeLevel: endingSailingHold ? nil : mode.sailingResumeLevel
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateSystemChargeHold(draining: Bool, holdingBelowLimit: Bool, chargingPastLimit: Bool) {
        guard draining != mode.systemIsDischargingToLimit
            || holdingBelowLimit != mode.systemIsHoldingBelowLimit
            || chargingPastLimit != mode.systemIsChargingPastLimit else { return }
        let newAppChargingMode = AppChargingMode(
            mode: mode.mode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: draining,
            systemIsHoldingBelowLimit: holdingBelowLimit,
            systemIsChargingPastLimit: chargingPastLimit,
            isHoldingFullChargeUntilUnplugged: mode.isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: mode.isAwaitingModeForChargerChange,
            sailingResumeLevel: mode.sailingResumeLevel
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateHoldingFullChargeUntilUnplugged(_ holding: Bool) {
        guard holding != mode.isHoldingFullChargeUntilUnplugged else { return }
        let newAppChargingMode = AppChargingMode(
            mode: mode.mode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: mode.systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: mode.systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: mode.systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: holding,
            isAwaitingModeForChargerChange: mode.isAwaitingModeForChargerChange,
            sailingResumeLevel: mode.sailingResumeLevel
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateSailingHold(_ resumeLevel: Int?) {
        guard resumeLevel != mode.sailingResumeLevel else { return }
        let newAppChargingMode = AppChargingMode(
            mode: mode.mode,
            userTempOverride: mode.userTempOverride,
            chargerConnected: mode.chargerConnected,
            systemIsDischargingToLimit: mode.systemIsDischargingToLimit,
            systemIsHoldingBelowLimit: mode.systemIsHoldingBelowLimit,
            systemIsChargingPastLimit: mode.systemIsChargingPastLimit,
            isHoldingFullChargeUntilUnplugged: mode.isHoldingFullChargeUntilUnplugged,
            isAwaitingModeForChargerChange: mode.isAwaitingModeForChargerChange,
            sailingResumeLevel: resumeLevel
        )
        setAppChargingMode(newAppChargingMode)
    }

    func updateOverride(_ override: UserTempChargingMode?) {
        setAppChargingMode(mode.replacingOverride(override))
    }

    func endOverride(_ ending: UserTempChargingMode, with end: OverrideEnd) {
        setAppChargingMode(mode.endingOverride(ending, with: end))
    }

    func updateChargerConnected(_ connected: Bool, awaitingMode: Bool) {
        setAppChargingMode(mode.withChargerConnected(connected, awaitingMode: awaitingMode))
    }

    /// Kept apart from `mode`, and posted on its own name: nothing that follows the charging
    /// state — history, banners, the MagSafe colour — is told of it.
    func updatePauseContext(_ context: PauseHoldContext?) {
        guard context != pauseContext else { return }
        pauseContext = context
        NotificationCenter.default.post(name: PauseContextDidChangeNotificationName, object: context.map(PauseContextBox.init))
    }

    func updateLidOpened(_ lidOpened: Bool) {
        guard lidOpened != self.lidOpened else { return }
        self.lidOpened = lidOpened
    }

    /// Posts on any change, the resume level alone included, so a rule edited during a sailing
    /// hold re-drives the charging pass the way a slider move does.
    func updateAutomationTarget(_ target: AutomationTarget?) {
        guard target != automationTarget else { return }
        automationTarget = target
        NotificationCenter.default.post(name: AutomationTargetDidChangeNotificationName, object: target)
    }

}
