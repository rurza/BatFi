//
//  PauseHoldsTests.swift
//  BatFi
//
//  A pause is offered, and armed, only where it would hold. Under Apple's charge limit the
//  value it puts in force is the frozen level as the apply will put it — raised to the floor
//  on a Mac whose limit cannot go below 80 — and it holds only if that is not above the
//  battery, which would charge it, and, for a discharge, is above the limit the discharge is
//  heading to, which it would otherwise go on to.
//

import Foundation
import Shared
import Testing

@testable import AppShared

@Suite struct PauseHoldsTests {
    private func mode(_ mode: ChargingMode, draining: Bool = false, override: UserTempChargingMode? = nil) -> AppChargingMode {
        AppChargingMode(
            mode: mode,
            userTempOverride: override,
            chargerConnected: true,
            systemIsDischargingToLimit: draining
        )
    }

    private func offered(
        _ state: AppChargingMode,
        level: Int,
        target: Int?,
        floor: Int?,
        backend: ChargeBackend? = .systemChargeLimit
    ) -> ManualInhibit.Pause? {
        ManualInhibit.pauseOffered(
            for: state,
            backend: backend,
            context: PauseHoldContext(dischargeTarget: target, floor: floor),
            batteryLevel: level
        )
    }

    private func armed(
        _ state: AppChargingMode,
        level: Int,
        target: Int?,
        floor: Int?,
        backend: ChargeBackend? = .systemChargeLimit
    ) -> UserTempChargingMode? {
        ManualInhibit.pause(
            for: state,
            batteryLevel: level,
            backend: backend,
            context: PauseHoldContext(dischargeTarget: target, floor: floor)
        )
    }

    // MARK: - The floor

    /// A Shortcuts limit of 55 under an 80 floor took the battery to 60. Frozen at 60, applied
    /// as 80: it would charge under "Discharging paused at 60%".
    @Test func aDischargePauseUnderTheFloorIsNotOffered() {
        let state = mode(.forceDischarge, override: UserTempChargingMode(limit: 55))
        #expect(offered(state, level: 60, target: 55, floor: 80) == nil)
        #expect(StatusMenuCommands.pauseTitle(mode: state, backend: .systemChargeLimit, context: PauseHoldContext(dischargeTarget: 55, floor: 80), batteryLevel: 60) == nil)
        #expect(armed(state, level: 60, target: 55, floor: 80) == nil)
    }

    @Test func aChargingPauseUnderTheFloorIsNotOffered() {
        #expect(offered(mode(.charging), level: 65, target: 80, floor: 80) == nil)
        #expect(armed(mode(.charging), level: 65, target: 80, floor: 80) == nil)
    }

    /// macOS 27 with a path below 80: no floor, held as asked.
    @Test func withoutAFloorASubEightyPauseHolds() {
        #expect(offered(mode(.charging), level: 65, target: 70, floor: nil) == .charging)
        #expect(offered(mode(.forceDischarge, override: UserTempChargingMode(limit: 0)), level: 60, target: 0, floor: nil) == .discharging)
    }

    /// From 80 up the frozen value never exceeds the level, floor or not.
    @Test func fromEightyUpTheFloorChangesNothing() {
        #expect(offered(mode(.charging), level: 87, target: 90, floor: 80) == .charging)
    }

    /// The inhibit backends hold the exact level with their own inhibit.
    @Test func theInhibitBackendsAreNotJudgedByAFloorOrATarget() {
        #expect(offered(mode(.charging), level: 60, target: 80, floor: 80, backend: .chte) == .charging)
        #expect(offered(mode(.forceDischarge), level: 60, target: 80, floor: 80, backend: .chte) == .discharging)
    }

    // MARK: - The target the discharge is heading to

    /// Limit 80, battery 84: frozen at 80, which is where macOS is draining to already.
    @Test func aDischargePauseThatRoundsToTheTargetIsNotOffered() {
        let draining = mode(.inhibit, draining: true)
        #expect(offered(draining, level: 84, target: 80, floor: nil) == nil)
        #expect(armed(draining, level: 84, target: 80, floor: nil) == nil)
    }

    @Test func aDischargePauseAboveTheTargetIsOffered() {
        let draining = mode(.inhibit, draining: true)
        #expect(offered(draining, level: 85, target: 80, floor: nil) == .discharging)
        #expect(armed(draining, level: 85, target: 80, floor: nil)?.limit == 85)
    }

    /// Run on Battery on an 80-floor Mac at 82%: BatFi's discharge heads to 0, not to the 80 in
    /// force, so a pause frozen at 80 does stop it.
    @Test func batFisOwnDischargeIsJudgedAgainstItsOwnTarget() {
        let runOnBattery = mode(.forceDischarge, override: UserTempChargingMode(limit: 0))
        #expect(offered(runOnBattery, level: 82, target: 0, floor: 80) == .discharging)
        #expect(armed(runOnBattery, level: 82, target: 0, floor: 80)?.limit == 80)
    }

    /// Paused at 85 with the battery at 87, resumed to a 70 limit, paused again at once: the
    /// target is the 70 the drain heads to, not the 85 powerd is still enforcing.
    @Test func aQuickRePauseAfterResumeIsOffered() {
        let target = ManualInhibit.dischargeTarget(overrideInForce: nil, resumedLimit: 70, floor: nil)
        #expect(target == 70)
        #expect(offered(mode(.inhibit, draining: true), level: 87, target: target, floor: nil) == .discharging)
        // On an 80-floor Mac the drain heads to 80, and 85 is above it.
        let floored = ManualInhibit.dischargeTarget(overrideInForce: nil, resumedLimit: 70, floor: 80)
        #expect(floored == 80)
        #expect(offered(mode(.inhibit, draining: true), level: 87, target: floored, floor: 80) == .discharging)
    }

    @Test func theTargetOfAPlainOverrideIsItsOwnLimit() {
        #expect(ManualInhibit.dischargeTarget(overrideInForce: UserTempChargingMode(limit: 0), resumedLimit: 80, floor: 80) == 0)
        #expect(ManualInhibit.dischargeTarget(overrideInForce: UserTempChargingMode(limit: 85, isInhibit: true), resumedLimit: 70, floor: 80) == 80)
    }

    /// No target known: judged by the level and the floor alone.
    @Test func noTargetIsNotJudgedAgainstOne() {
        #expect(offered(mode(.inhibit, draining: true), level: 84, target: nil, floor: nil) == .discharging)
    }

    /// Before the first pass has published a context, or with no reading, the mode alone
    /// decides, as before.
    @Test func noContextOffersByTheModeAlone() {
        let draining = mode(.inhibit, draining: true)
        #expect(ManualInhibit.pauseOffered(for: draining, backend: .systemChargeLimit) == .discharging)
        #expect(ManualInhibit.pauseOffered(for: draining, backend: .systemChargeLimit, context: PauseHoldContext(dischargeTarget: 80, floor: nil), batteryLevel: nil) == .discharging)
    }
}
