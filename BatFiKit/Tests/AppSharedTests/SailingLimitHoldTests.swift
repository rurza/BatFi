//
//  SailingLimitHoldTests.swift
//  BatFi
//
//  The limit a sailing hold keeps in force where macOS enforces the limit and BatFi only sets
//  its value: nothing new written for a hold that began at the limit, the limit frozen at the
//  current charge for one that began inside the range, and nothing written at all for as long
//  as the hold lasts.
//

import Foundation
import Shared
import Testing

@testable import AppShared

@Suite struct SailingLimitHoldTests {
    @Test func holdThatBeganAtTheLimitWritesNothingNew() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80) == 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 74, limitInForce: 80, otherwise: 80) == 80)
    }

    @Test func connectionInsideTheRangeFreezesAtTheCurrentCharge() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80) == 76)
    }

    @Test func levelChangesDuringAHoldWriteNothing() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 76, otherwise: 90) == 76)
        // A limit lowered under the battery cannot start a charge: the hold moves down to it,
        // and macOS drains to it as it does with sailing off.
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 75, limitInForce: 76, otherwise: 60) == 60)
        #expect(hold.heldLimit == 60)
    }

    // MARK: - The limit moved during a hold

    @Test func aLimitLoweredToTheBatteryMovesTheHold() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 75, limitInForce: 80, otherwise: 75) == 75)
        #expect(hold.heldLimit == 75)
    }

    /// A value above the battery would start a charge: it waits for the next charging phase.
    @Test func aLimitLoweredToJustAboveTheBatteryWaits() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 74, limitInForce: 80, otherwise: 75) == 80)
        #expect(hold.heldLimit == 80)
    }

    @Test func aLimitRaisedDuringAHoldWaits() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 79, limitInForce: 80, otherwise: 90) == 80)
        #expect(hold.heldLimit == 80)
    }

    /// From 80 up the moved value is rounded down to a step of five, as a freeze is: 87 asked
    /// for would be applied as 90, over a battery at 88.
    @Test func aLimitLoweredFromEightyUpRoundsDownLikeAFreeze() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 90, limitInForce: 90, otherwise: 90)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 88, limitInForce: 90, otherwise: 87) == 85)
        #expect(hold.heldLimit == 85)
    }

    /// A sub-80 limit is enforced at the learned floor; over a battery under the floor that
    /// would start a charge, so it waits.
    @Test func aLimitLoweredUnderALearnedFloorIsJudgedAtTheFloor() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 60, floor: 80) == 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 60, floor: nil) == 60)
    }

    // MARK: - The limit macOS enforces

    /// From 80 up macOS takes a step of five and rounds an off-step request up; below 80 the
    /// learned floor applies.
    @Test func theLimitMacOSEnforcesIncludesItsRounding() {
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 87, floor: nil) == 90)
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 97, floor: nil) == 100)
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 85, floor: nil) == 85)
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 80, floor: 80) == 80)
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 100, floor: nil) == 100)
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 73, floor: nil) == 73)
        #expect(SailingLimitHold.limitMacOSEnforces(requested: 73, floor: 80) == 80)
    }

    @Test func phaseEndingReleasesTheHeldLimit() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .charging, backend: .systemChargeLimit, batteryLevel: 69, limitInForce: 76, otherwise: 85) == 85)
        #expect(hold.heldLimit == nil)
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: nil, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 76, otherwise: 80) == 80)
    }

    @Test func otherBackendsAreUntouched() {
        var hold = SailingLimitHold()
        for backend: ChargeBackend? in [.chte, .legacyCH0BC, .firmwareRange, nil] {
            #expect(hold.requestedLimit(phase: .holding, backend: backend, batteryLevel: 76, limitInForce: 80, otherwise: 80) == 80)
            #expect(hold.heldLimit == nil)
        }
    }

    @Test func freezeAtOrAboveEightyRoundsDownLikeManualPause() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 87, limitInForce: 90, otherwise: 90) == 85)
    }

    @Test func freezeCannotHoldUnderALearnedFloor() {
        #expect(!SailingLimitHold.freezeCanHold(batteryLevel: 76, floor: 80))
        #expect(SailingLimitHold.freezeCanHold(batteryLevel: 76, floor: nil))
        #expect(SailingLimitHold.freezeCanHold(batteryLevel: 87, floor: 80))
    }

    // MARK: - What a hold may keep on entry

    /// A value left behind by a discharge ("Run on Battery" asks for 0) sits under the battery,
    /// and kept as the hold it would have macOS drain the battery on mains power.
    @Test func aDischargeTargetLeftInForceIsNeverKept() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 0, otherwise: 80) == 76)
    }

    /// A manual pause's frozen value is the battery's own level: the hold after it carries it
    /// on, and nothing new is written.
    @Test func aPauseFrozenAtTheBatteryIsKept() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 76, otherwise: 80) == 76)
        var high = SailingLimitHold()
        #expect(high.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 87, limitInForce: 85, otherwise: 90) == 85)
    }

    /// At or above the limit the hold is the limit: a battery above it drains to it, as it does
    /// with sailing off — whatever was applied before, and when nothing has been applied yet.
    @Test(arguments: [nil, 0, 76, 85] as [Int?])
    func aHoldAtOrAboveTheLimitHoldsTheLimit(limitInForce: Int?) {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 85, limitInForce: limitInForce, otherwise: 80) == 80)
    }

    @Test func nothingAppliedYetInsideTheRangeFreezes() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: nil, otherwise: 80) == 76)
    }

    // MARK: - Frozen or not

    @Test func aHoldAtTheLimitIsNotAFreeze() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(!hold.keepsAValueOtherThan(80))
        // The levels moved during the hold: the value kept is no longer the person's.
        #expect(hold.keepsAValueOtherThan(90))
    }

    @Test func aHoldInsideTheRangeIsAFreeze() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80)
        #expect(hold.keepsAValueOtherThan(80))
        #expect(!SailingLimitHold().keepsAValueOtherThan(80))
    }

    // MARK: - A hot battery during a hold

    /// A hot battery's hold freezes under the sailing hold's value (held 80, battery drifted to
    /// 76): the sailing hold takes the hot value over, as it takes over a manual pause's, so
    /// cooling down writes nothing — going back to 80 would be a change, and a change starts a
    /// charge the label would call "on hold".
    @Test func aHotHoldUnderTheHeldValueIsTakenOver() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80, hotBatteryHoldLimit: 76) == 76)
        #expect(hold.heldLimit == 76)
        // Cooled: the hot hold is gone, the sailing hold keeps its value.
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 76, otherwise: 80) == 76)
        #expect(hold.keepsAValueOtherThan(80))
    }

    @Test func aHotHoldAboveTheHeldValueChangesNothing() {
        var hold = SailingLimitHold()
        _ = hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80)
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 77, limitInForce: 76, otherwise: 80, hotBatteryHoldLimit: 77) == 76)
        #expect(hold.heldLimit == 76)
    }

    /// Entering a hold while a hot battery is held: the hold starts at the hot value.
    @Test func aHoldThatBeginsUnderAHotHoldKeepsTheHotValue() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 78, otherwise: 80, hotBatteryHoldLimit: 78) == 78)
        #expect(hold.heldLimit == 78)
    }

    @Test func aHotHoldOutsideAHoldIsLeftToTheHotHold() {
        var hold = SailingLimitHold()
        #expect(hold.requestedLimit(phase: .charging, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80, hotBatteryHoldLimit: 76) == 80)
        #expect(hold.heldLimit == nil)
    }

    // MARK: - Holds this Mac cannot express

    @Test func enteringAHoldInsideTheRangeUnderALearnedFloorCannotHold() {
        let hold = SailingLimitHold()
        #expect(hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80, floor: 80))
        #expect(!hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80, floor: nil))
        // From 80 up the freeze takes the 5-point step, which this Mac does honour.
        #expect(!hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 87, limitInForce: 90, otherwise: 90, floor: 80))
    }

    /// A sub-80 limit is applied at the floor, so a battery under the floor is inside the range
    /// even where the request itself is under the battery.
    @Test func theLimitIsJudgedWhereTheFloorPutsIt() {
        let hold = SailingLimitHold()
        #expect(hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 75, limitInForce: 80, otherwise: 70, floor: 80))
    }

    @Test func onlyAnEntryThatWouldFreezeIsJudged() {
        // At the limit: nothing frozen.
        #expect(!SailingLimitHold().cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80, floor: 80))
        // Not holding, or not this backend.
        #expect(!SailingLimitHold().cannotHoldOnEntry(phase: .charging, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80, floor: 80))
        #expect(!SailingLimitHold().cannotHoldOnEntry(phase: .holding, backend: .chte, batteryLevel: 76, limitInForce: 80, otherwise: 80, floor: 80))
        // Already holding: the hold goes on with what it has.
        var holding = SailingLimitHold()
        _ = holding.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: 80, limitInForce: 80, otherwise: 80)
        #expect(!holding.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 76, limitInForce: 80, otherwise: 80, floor: 80))
    }

    @Test func aHoldTheApplyRaisedAboveTheBatteryCannotHold() {
        // The first sub-80 request of a process on a Mac with a floor: asked 76, applied 80.
        #expect(SailingLimitHold.applyRaisedItAboveTheBattery(requested: 76, applied: 80, batteryLevel: 76))
        // A hold at the limit the battery has since drifted under: applied as asked.
        #expect(!SailingLimitHold.applyRaisedItAboveTheBattery(requested: 80, applied: 80, batteryLevel: 74))
        // A failed apply says nothing.
        #expect(!SailingLimitHold.applyRaisedItAboveTheBattery(requested: 76, applied: nil, batteryLevel: 76))
    }

    /// A rule's or a shortcut's 87 is enforced as 90 and the helper reports 90 applied. The
    /// hold that began there at 90 keeps 87, and the battery drifts down to the resume level:
    /// the phase stays holding, nothing new is requested, and the 87 → 90 rounding is never
    /// read as the apply raising the hold above the battery.
    @Test func anOffStepLimitHoldsAllTheWayDownToTheResumeLevel() {
        let enforced = SailingLimitHold.limitMacOSEnforces(requested: 87, floor: nil)
        let levels = SailingLevels(limit: enforced, resumeLevel: 80)
        var tracker = SailingPhaseTracker()
        var hold = SailingLimitHold()
        // Charging up to the limit first, so the hold begins at it.
        _ = tracker.advance(chargerConnected: true, levels: levels, overrideInForce: nil, batteryLevel: 70)
        for battery in (80...90).reversed() {
            let phase = tracker.advance(chargerConnected: true, levels: levels, overrideInForce: nil, batteryLevel: battery)
            #expect(phase == .holding, "battery \(battery)")
            let requested = hold.requestedLimit(
                phase: phase, backend: .systemChargeLimit, batteryLevel: battery, limitInForce: enforced, otherwise: 87
            )
            #expect(requested == 87, "battery \(battery)")
            #expect(
                !SailingLimitHold.applyRaisedItAboveTheBattery(requested: requested, applied: enforced, batteryLevel: battery),
                "battery \(battery)"
            )
        }
        // Below the resume level the charge resumes as usual.
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: nil, batteryLevel: 79) == .charging)
    }

    /// A rule's or a shortcut's 87 is enforced as 90. A charger connected at 88 is under the
    /// limit macOS enforces, and a new connection makes macOS charge to it: holding "at the
    /// limit" there would say "on hold" over a battery charging 88 → 90. It charges to the
    /// limit first, labelled as charging, and holds from 90.
    @Test(arguments: [88, 89])
    func anEntryBetweenAnOffStepLimitAndWhereMacOSEnforcesItChargesFirst(battery: Int) {
        let hold = SailingLimitHold()
        #expect(hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: battery, limitInForce: 90, otherwise: 87, floor: nil))
        #expect(hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: battery, limitInForce: nil, otherwise: 87, floor: nil))
        // At the enforced value itself the hold begins at the limit.
        #expect(!hold.cannotHoldOnEntry(phase: .holding, backend: .systemChargeLimit, batteryLevel: 90, limitInForce: 90, otherwise: 87, floor: nil))
        // Were the entry reached anyway, it never asks for the off-step limit over a battery
        // under 90: that request is a charge to 90.
        var entered = SailingLimitHold()
        #expect(entered.requestedLimit(phase: .holding, backend: .systemChargeLimit, batteryLevel: battery, limitInForce: 90, otherwise: 87) != 87)
    }

    /// A pause ending at 88 under 87 leaves the pause's frozen 85 in force. The fresh phase is
    /// holding, but the hold would request 87 — a change macOS enforces as 90, which charges.
    /// It charges to the limit first, and the walk then holds from 90 down to the resume level.
    @Test func aPauseEndingBetweenAnOffStepLimitAndWhereMacOSEnforcesItChargesFirst() {
        let enforced = SailingLimitHold.limitMacOSEnforces(requested: 87, floor: nil)
        let levels = SailingLevels(limit: enforced, resumeLevel: 80)
        var tracker = SailingPhaseTracker()
        var hold = SailingLimitHold()
        let pause = UserTempChargingMode(limit: 85, isInhibit: true)
        _ = tracker.advance(chargerConnected: true, levels: nil, overrideInForce: pause, batteryLevel: 88)
        var phase = tracker.advance(chargerConnected: true, levels: levels, overrideInForce: nil, batteryLevel: 88)
        #expect(phase == .holding)
        #expect(hold.cannotHoldOnEntry(phase: phase, backend: .systemChargeLimit, batteryLevel: 88, limitInForce: 85, otherwise: 87, floor: nil))
        tracker.chargeToLimitFirst()
        phase = tracker.phase
        #expect(hold.requestedLimit(phase: phase, backend: .systemChargeLimit, batteryLevel: 88, limitInForce: 85, otherwise: 87) == 87)
        #expect(tracker.advance(chargerConnected: true, levels: levels, overrideInForce: nil, batteryLevel: 89) == .charging)
        phase = tracker.advance(chargerConnected: true, levels: levels, overrideInForce: nil, batteryLevel: 90)
        #expect(phase == .holding)
        #expect(!hold.cannotHoldOnEntry(phase: phase, backend: .systemChargeLimit, batteryLevel: 90, limitInForce: 90, otherwise: 87, floor: nil))
        #expect(hold.requestedLimit(phase: phase, backend: .systemChargeLimit, batteryLevel: 90, limitInForce: 90, otherwise: 87) == 87)
    }

    @Test func onlyARaisePastTheRoundingCountsAsTheApplyRaisingTheHold() {
        // A Mac that refuses below 80: 76 asked over a battery at 76, applied as 80.
        #expect(SailingLimitHold.applyRaisedItAboveTheBattery(requested: 76, applied: 80, batteryLevel: 76))
        // 87 applied as 90 is macOS's step, not a raise, wherever the battery sits.
        #expect(!SailingLimitHold.applyRaisedItAboveTheBattery(requested: 87, applied: 90, batteryLevel: 88))
        // 97 is enforced as 100.
        #expect(!SailingLimitHold.applyRaisedItAboveTheBattery(requested: 97, applied: 100, batteryLevel: 98))
    }
}
