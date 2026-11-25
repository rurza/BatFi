//
//  AutoLowPowerModeEvaluationTests.swift
//  BatFi
//
//  Unit tests for the glue between the automatic Low Power Mode policy and the manager that
//  carries it out: when the helper is worth asking, how a reconcile chains into a fresh
//  decision, which side effects a decision stands for, and what quitting does.
//

import Foundation
import Testing

@testable import Shared

@Suite struct AutoLowPowerModeEvaluationTests {
    private typealias Policy = AutoLowPowerModePolicy
    private typealias Evaluation = AutoLowPowerModeEvaluation
    private typealias Decision = AutoLowPowerModePolicy.Decision

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func live(battery: UInt8?, ac: UInt8? = 0, usesPowermodeKey: Bool = true) -> PowerModeBySource {
        PowerModeBySource(battery: battery, ac: ac, usesPowermodeKey: usesPowermodeKey)
    }

    private func record(previous: UInt8 = 0, acAtWrite: UInt8? = 0, usesPowermodeKey: Bool = true) -> AutoLowPowerModeRecord {
        AutoLowPowerModeRecord(
            usesPowermodeKey: usesPowermodeKey,
            previousBatteryValue: previous,
            acValueAtWrite: acAtWrite,
            engagedAt: now
        )
    }

    private func input(
        enabled: Bool = true,
        license: LicenseStatus = .valid,
        threshold: Int = 20,
        onBattery: Bool = true,
        level: Int,
        live: PowerModeBySource? = nil,
        record: AutoLowPowerModeRecord? = nil,
        yieldedUntilCharge: Bool = false
    ) -> Policy.Input {
        Policy.Input(
            enabled: enabled,
            license: license,
            threshold: threshold,
            onBattery: onBattery,
            batteryLevel: level,
            live: live,
            record: record,
            yieldedUntilCharge: yieldedUntilCharge,
            now: now
        )
    }

    // MARK: When the helper is asked

    @Test func asksWheneverARecordIsHeldWhateverElseIsTrue() {
        // Disabled, on the charger, far above the threshold: every one of these is a reason
        // to *give back*, and giving back needs the live value.
        #expect(Evaluation.needsLiveState(input(enabled: false, onBattery: false, level: 90, record: record())))
        #expect(Evaluation.needsLiveState(input(level: 90, record: record(), yieldedUntilCharge: true)))
        // Nor does the licence change that: losing it is a reason to give back, and while it
        // is not read yet every other reason still is.
        #expect(Evaluation.needsLiveState(input(license: .invalid, level: 10, record: record())))
        #expect(Evaluation.needsLiveState(input(license: .unknown, level: 10, record: record())))
    }

    @Test func asksWithoutARecordOnlyWhereTheFeatureCouldEngage() {
        #expect(Evaluation.needsLiveState(input(level: 20)))
        #expect(Evaluation.needsLiveState(input(level: 5)))
    }

    @Test func doesNotAskWithoutARecordWhereNothingCouldEngage() {
        #expect(!Evaluation.needsLiveState(input(enabled: false, level: 10)))
        #expect(!Evaluation.needsLiveState(input(onBattery: false, level: 10)))
        #expect(!Evaluation.needsLiveState(input(level: 10, yieldedUntilCharge: true)))
        #expect(!Evaluation.needsLiveState(input(level: 21)))
        // Zero is an unread level, which the policy never acts on.
        #expect(!Evaluation.needsLiveState(input(level: 0)))
        // Without a valid licence nothing engages, so there is nothing to ask for.
        #expect(!Evaluation.needsLiveState(input(license: .invalid, level: 10)))
        #expect(!Evaluation.needsLiveState(input(license: .unknown, level: 10)))
    }

    /// The claim that makes skipping the round trip safe: wherever the gate says "don't ask",
    /// no live value could have produced a different decision than not knowing it does —
    /// same write (none), same record (kept), same latch.
    @Test func skippingTheReadNeverChangesTheOutcome() {
        let lives: [PowerModeBySource?] = [
            nil,
            live(battery: 0), live(battery: 1), live(battery: 2),
            live(battery: 0, ac: 1), live(battery: 1, ac: 1),
            live(battery: 0, usesPowermodeKey: false), live(battery: 1, usesPowermodeKey: false),
        ]
        for enabled in [true, false] {
            for license in [LicenseStatus.valid, .invalid, .unknown] {
                for onBattery in [true, false] {
                    for yielded in [true, false] {
                        for level in [0, 1, 19, 20, 21, 24, 25, 60, 100] {
                            let blind = input(
                                enabled: enabled,
                                license: license,
                                onBattery: onBattery,
                                level: level,
                                yieldedUntilCharge: yielded
                            )
                            guard !Evaluation.needsLiveState(blind) else { continue }
                            let unknown = Policy.decide(blind)
                            for value in lives {
                                var informed = blind
                                informed.live = value
                                let decision = Policy.decide(informed)
                                #expect(decision.write == nil)
                                #expect(decision.record == .keep)
                                #expect(decision.yieldedUntilCharge == unknown.yieldedUntilCharge)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Reconcile, then decide again

    @Test func withoutAReconcileItIsPlainDecide() {
        let owned = input(level: 30, live: live(battery: 1), record: record())
        #expect(Evaluation.decisions(owned, reconcile: false) == [Policy.decide(owned)])
    }

    /// The helper restarted and put the value back on its way out. The stale record goes
    /// without the hand-back latch, and BatFi turns Low Power Mode straight back on rather
    /// than waiting for the next trigger.
    @Test func aReconcileThatClearsAStaleRecordDecidesAgainAndReEngages() {
        let stale = input(level: 15, live: live(battery: 0, ac: 0), record: record(previous: 0, acAtWrite: 0))
        let decisions = Evaluation.decisions(stale, reconcile: true)
        #expect(decisions.count == 2)
        #expect(decisions.first?.reason == .alreadyRestoredByHelper)
        #expect(decisions.first?.record == .clear)
        #expect(decisions.first?.write == nil)
        #expect(decisions.last == Decision(
            write: 1,
            record: .set(record(previous: 0, acAtWrite: 0)),
            yieldedUntilCharge: false,
            reason: .engaged
        ))
    }

    @Test func aReconcileThatClearsAStaleRecordAboveTheThresholdStaysOff() {
        let stale = input(level: 60, live: live(battery: 2, ac: 0), record: record(previous: 2, acAtWrite: 0))
        let decisions = Evaluation.decisions(stale, reconcile: true)
        #expect(decisions.map(\.reason) == [.alreadyRestoredByHelper, .aboveThreshold])
        #expect(decisions.last?.write == nil)
    }

    /// The follow-up decision inherits the latch the reconcile left, not the one it started
    /// from — so a hand-back that is still in force keeps BatFi out.
    @Test func theFollowUpDecisionCarriesTheLatch() {
        let stale = input(
            level: 15,
            live: live(battery: 0, ac: 0),
            record: record(previous: 0, acAtWrite: 0),
            yieldedUntilCharge: true
        )
        let decisions = Evaluation.decisions(stale, reconcile: true)
        #expect(decisions.map(\.reason) == [.alreadyRestoredByHelper, .yieldedUntilCharge])
        #expect(decisions.last?.yieldedUntilCharge == true)
    }

    @Test func aReconcileOfARecordStillHeldIsASingleDecision() {
        let owned = input(level: 15, live: live(battery: 1, ac: 0), record: record(previous: 0, acAtWrite: 0))
        #expect(Evaluation.decisions(owned, reconcile: true).map(\.reason) == [.holding])
    }

    /// A user change is still a hand-back, latch and all; only the exact previous value
    /// reads as the helper's own restore.
    @Test func aReconcileOfAUserChangeHandsBackWithoutDecidingAgain() {
        let changed = input(level: 15, live: live(battery: 2, ac: 0), record: record(previous: 0, acAtWrite: 0))
        let decisions = Evaluation.decisions(changed, reconcile: true)
        #expect(decisions.map(\.reason) == [.handedBackToUser])
        #expect(decisions.first?.yieldedUntilCharge == true)
    }

    // MARK: Reconcile, and the licence

    /// A crash left a record the helper has since given back. That is cleared whatever the
    /// licence says — and without one, nothing is turned back on.
    @Test func aStaleRecordIsClearedWithoutALicenceAndNothingEngages() {
        for license in [LicenseStatus.invalid, .unknown] {
            let stale = input(license: license, level: 15, live: live(battery: 0, ac: 0), record: record(previous: 0, acAtWrite: 0))
            let decisions = Evaluation.decisions(stale, reconcile: true)
            #expect(decisions.map(\.reason) == [.alreadyRestoredByHelper, .disabled])
            #expect(decisions.allSatisfy { $0.write == nil })
            #expect(decisions.last?.yieldedUntilCharge == false)
        }
    }

    /// A record an earlier run left and BatFi still owns is kept while the licence is being
    /// read, and the helper that may have just started is armed with it again.
    @Test func aRecordStillOwnedAtLaunchIsKeptAndReArmedWhileTheLicenceIsRead() {
        let held = record(previous: 0, acAtWrite: 0)
        let owned = input(license: .unknown, level: 15, live: live(battery: 1, ac: 0), record: held)
        let decisions = Evaluation.decisions(owned, reconcile: true)
        #expect(decisions.map(\.reason) == [.holding])
        #expect(decisions.map { Evaluation.step(for: $0, heldRecord: held, afterReconcile: true) } == [.rearm(held)])
    }

    /// Once the licence reads not valid, the same record is given back.
    @Test func aRecordStillOwnedAtLaunchIsGivenBackWithoutALicence() {
        let held = record(previous: 0, acAtWrite: 0)
        let owned = input(license: .invalid, level: 15, live: live(battery: 1, ac: 0), record: held)
        let decisions = Evaluation.decisions(owned, reconcile: true)
        #expect(decisions.map(\.reason) == [.restoredBecauseDisabled])
        #expect(decisions.last?.yieldedUntilCharge == false)
        #expect(decisions.map { Evaluation.step(for: $0, heldRecord: held, afterReconcile: true) } == [.restore(value: 0, record: held)])
    }

    // MARK: What a decision stands for

    @Test func anEngageDecisionIsAnEngageStep() {
        let decision = Policy.decide(input(level: 15, live: live(battery: 0)))
        #expect(Evaluation.step(for: decision, heldRecord: nil, afterReconcile: false) == .engage(record(previous: 0)))
    }

    @Test func aRestoreDecisionWritesThePreviousValueOfTheHeldRecord() {
        let held = record(previous: 2)
        let decision = Policy.decide(input(onBattery: false, level: 15, live: live(battery: 1), record: held))
        #expect(decision.reason == .restoredOnCharger)
        #expect(Evaluation.step(for: decision, heldRecord: held, afterReconcile: false) == .restore(value: 2, record: held))
    }

    @Test func aHandBackAndAHelperRestoreAreBothForgetSteps() {
        let held = record(previous: 0)
        let handBack = Policy.decide(input(level: 15, live: live(battery: 0, ac: 1), record: held))
        #expect(handBack.reason == .handedBackToUser)
        #expect(Evaluation.step(for: handBack, heldRecord: held, afterReconcile: false) == .forget)

        let restoredByHelper = Policy.reconcileAtLaunch(input(level: 15, live: live(battery: 0), record: held))
        #expect(restoredByHelper.reason == .alreadyRestoredByHelper)
        #expect(Evaluation.step(for: restoredByHelper, heldRecord: held, afterReconcile: true) == .forget)
    }

    /// A healthy edge can mean a new helper process, which has nothing armed; the record
    /// BatFi still holds has to be handed to it again.
    @Test func holdingAfterAReconcileReArmsTheHelper() {
        let held = record(previous: 0)
        let holding = Policy.reconcileAtLaunch(input(level: 15, live: live(battery: 1), record: held))
        #expect(holding.reason == .holding)
        #expect(Evaluation.step(for: holding, heldRecord: held, afterReconcile: true) == .rearm(held))
        #expect(Evaluation.step(for: holding, heldRecord: held, afterReconcile: false) == .none)
    }

    @Test func decisionsThatChangeNothingAreNoSteps() {
        #expect(Evaluation.step(for: Policy.decide(input(level: 50, live: live(battery: 0))), heldRecord: nil, afterReconcile: false) == .none)
        #expect(Evaluation.step(for: Policy.decide(input(level: 15, live: nil, record: record())), heldRecord: record(), afterReconcile: false) == .none)
        #expect(Evaluation.step(for: Policy.decide(input(level: 15, live: live(battery: 1))), heldRecord: nil, afterReconcile: true) == .none)
    }

    /// A write with nothing held to take it from cannot be a restore; it is refused rather
    /// than guessed at.
    @Test func aRestoreWithNoHeldRecordIsNoStep() {
        let orphan = Decision(write: 0, record: .clear, yieldedUntilCharge: false, reason: .restoredOnCharger)
        #expect(Evaluation.step(for: orphan, heldRecord: nil, afterReconcile: false) == .none)
    }

    // MARK: After an engage write that failed

    /// The record the failed engage kept, and the reconcile it owed: the write never landed,
    /// so the setting is still what BatFi found. The record goes without the hand-back latch
    /// — the user did nothing — and, still low, BatFi tries again.
    @Test func aFailedEngageThatDidNotLandIsClearedWithoutTheLatch() {
        let kept = record(previous: 0, acAtWrite: 0)
        let decisions = Evaluation.decisions(
            input(level: 15, live: live(battery: 0, ac: 0), record: kept),
            reconcile: true
        )
        #expect(decisions.first == Decision(write: nil, record: .clear, yieldedUntilCharge: false, reason: .alreadyRestoredByHelper))
        #expect(decisions.last?.reason == .engaged)
        #expect(Evaluation.step(for: decisions[0], heldRecord: kept, afterReconcile: true) == .forget)
    }

    /// The write landed and only its reply was lost: Low Power Mode is BatFi's, and the helper
    /// — never armed for it — is armed now.
    @Test func aFailedEngageThatLandedIsStillHeld() {
        let kept = record(previous: 2, acAtWrite: 0)
        let decisions = Evaluation.decisions(
            input(level: 15, live: live(battery: 1, ac: 0), record: kept),
            reconcile: true
        )
        #expect(decisions == [Decision(write: nil, record: .keep, yieldedUntilCharge: false, reason: .holding)])
        #expect(Evaluation.step(for: decisions[0], heldRecord: kept, afterReconcile: true) == .rearm(kept))
    }

    // MARK: Telling the user

    private typealias Announcement = AutoLowPowerModeEvaluation.Announcement

    /// `announcement`, at the default threshold of 20 unless given another: the line a charge
    /// has to have crossed is then 25.
    private func announcement(
        onBattery: Bool = true,
        level: Int,
        threshold: Int = 20,
        engaged: Bool,
        announced: Bool
    ) -> Announcement {
        Evaluation.announcement(
            onBattery: onBattery,
            batteryLevel: level,
            threshold: threshold,
            engaged: engaged,
            announcedThisDischarge: announced
        )
    }

    @Test func theFirstEngageOfADischargeIsAnnounced() {
        #expect(announcement(level: 20, engaged: true, announced: false)
            == Announcement(post: true, announcedThisDischarge: true))
    }

    /// Quitting gives Low Power Mode back and the next launch turns it on again — after every
    /// update, say. The user was told the first time, and nothing has changed for them since.
    @Test func anEngageLaterInTheSameDischargeIsNotAnnouncedAgain() {
        #expect(announcement(level: 20, engaged: true, announced: true)
            == Announcement(post: false, announcedThisDischarge: true))
    }

    /// The charger ends the discharge, and with it the announcement's once — at any level,
    /// read or not.
    @Test func theChargerEndsTheDischarge() {
        for level in [0, 10, 20, 24, 25, 80] {
            for announced in [true, false] {
                #expect(announcement(onBattery: false, level: level, engaged: false, announced: announced)
                    == Announcement(post: false, announcedThisDischarge: false))
            }
        }
    }

    @Test func anEvaluationThatEngagesNothingOnBatteryKeepsWhatWasSaid() {
        for level in [1, 10, 20, 24] {
            for announced in [true, false] {
                #expect(announcement(level: level, engaged: false, announced: announced)
                    == Announcement(post: false, announcedThisDischarge: announced))
            }
        }
    }

    /// A charge BatFi did not see ends the discharge as well. On the battery the charge only
    /// falls, so being `hysteresis` points above the threshold means the Mac was charged
    /// since it was last low.
    @Test func aChargeBatFiDidNotSeeEndsTheDischarge() {
        #expect(announcement(level: 25, engaged: false, announced: true)
            == Announcement(post: false, announcedThisDischarge: false))
        #expect(announcement(level: 80, engaged: false, announced: true)
            == Announcement(post: false, announcedThisDischarge: false))
        #expect(announcement(level: 55, threshold: 50, engaged: false, announced: true)
            == Announcement(post: false, announcedThisDischarge: false))
    }

    @Test func justBelowTheLineTheDischargeGoesOn() {
        #expect(announcement(level: 24, engaged: false, announced: true)
            == Announcement(post: false, announcedThisDischarge: true))
        #expect(announcement(level: 54, threshold: 50, engaged: false, announced: true)
            == Announcement(post: false, announcedThisDischarge: true))
    }

    /// Zero is a level not read yet, which says nothing about a charge. The slider keeps the
    /// threshold at 5 or more, where zero is below the line anyway, but the threshold is
    /// whatever the defaults hold.
    @Test func aLevelNotReadYetDoesNotEndTheDischarge() {
        for threshold in [20, 0, -Policy.hysteresis] {
            #expect(announcement(level: 0, threshold: threshold, engaged: false, announced: true)
                == Announcement(post: false, announcedThisDischarge: true))
        }
    }

    /// The line is the policy's own: wherever the level gives back a Low Power Mode BatFi
    /// holds, the discharge it was announced in is over, and nowhere else.
    @Test func theLineIsWhereThePolicyGivesLowPowerModeBackForTheLevel() {
        for threshold in [5, 20, 50] {
            for level in 1...100 {
                let held = input(threshold: threshold, level: level, live: live(battery: 1), record: record())
                let givenBack = Policy.decide(held).reason == .restoredAboveThreshold
                let over = !announcement(level: level, threshold: threshold, engaged: false, announced: true)
                    .announcedThisDischarge
                #expect(over == givenBack, "level \(level), threshold \(threshold)")
            }
        }
    }

    /// The bug the once is for stays fixed: a relaunch anywhere below the line, on the
    /// battery, turns Low Power Mode on again without a word.
    @Test func aRelaunchBelowTheLineIsNotAnnouncedAgain() {
        for level in 1..<(20 + Policy.hysteresis) {
            // The first evaluation after the launch, then the engage it makes.
            let launch = announcement(level: level, engaged: false, announced: true)
            let engage = announcement(level: level, engaged: true, announced: launch.announcedThisDischarge)
            #expect(!engage.post, "level \(level)")
            #expect(engage.announcedThisDischarge)
        }
    }

    /// The case the once is for, end to end: turned on and announced, given back at quit,
    /// turned on again by the next launch without a word, then a charge and a new discharge
    /// that is announced afresh.
    @Test func aRelaunchIsQuietAndTheNextDischargeIsAnnounced() {
        var announced = false
        var posts = 0
        func evaluate(onBattery: Bool = true, level: Int, engaged: Bool) {
            let next = announcement(onBattery: onBattery, level: level, engaged: engaged, announced: announced)
            if next.post { posts += 1 }
            announced = next.announcedThisDischarge
        }

        evaluate(level: 20, engaged: true)
        #expect(posts == 1)
        // Quit gives it back; the relaunch, still on battery, turns it on again.
        evaluate(level: 19, engaged: false)
        evaluate(level: 19, engaged: true)
        #expect(posts == 1)
        // On the charger, then off it and low again.
        evaluate(onBattery: false, level: 80, engaged: false)
        evaluate(level: 80, engaged: false)
        evaluate(level: 20, engaged: true)
        #expect(posts == 2)
    }

    /// The Mac was charged with BatFi not running to see it — shut down low, charged, and
    /// started again on its battery. The next launch finds the discharge that was announced
    /// over, and the next time the battery runs low is announced afresh.
    @Test func aDischargeAfterAChargeBatFiDidNotSeeIsAnnounced() {
        var announced = false
        var posts = 0
        func evaluate(level: Int, engaged: Bool) {
            let next = announcement(level: level, engaged: engaged, announced: announced)
            if next.post { posts += 1 }
            announced = next.announcedThisDischarge
        }

        evaluate(level: 20, engaged: true)
        #expect(posts == 1)
        // Charged while BatFi was not running; the first evaluation after the launch.
        evaluate(level: 90, engaged: false)
        #expect(!announced)
        evaluate(level: 20, engaged: true)
        #expect(posts == 2)
    }

    /// Lowering the threshold past the line mid-discharge ends it as a charge would: the
    /// policy gives Low Power Mode back there, and turning it on again at the new threshold
    /// is news.
    @Test func aThresholdLoweredPastTheLineAnnouncesTheNextEngage() {
        let lowered = announcement(level: 18, threshold: 10, engaged: false, announced: true)
        #expect(!lowered.announcedThisDischarge)
        #expect(announcement(level: 10, threshold: 10, engaged: true, announced: lowered.announcedThisDischarge).post)
    }

    // MARK: Quitting

    /// Every quit line in the log carries a reason, spelled the way the policy's are.
    @Test func quitStepsHaveReasonsForTheLog() {
        #expect(Evaluation.QuitStep.restore.reason == "restoredAtQuit")
        #expect(Evaluation.QuitStep.handBack.reason == Policy.Reason.handedBackToUser.rawValue)
        #expect(Evaluation.QuitStep.leaveToHelper.reason == Policy.Reason.liveStateUnknown.rawValue)
    }

    @Test func quittingRestoresWhatIsStillBatFis() {
        let held = record(previous: 2, acAtWrite: 0)
        #expect(Evaluation.quitStep(record: held, live: live(battery: 1, ac: 0)) == .restore)
    }

    @Test func quittingHandsBackWhatTheUserHasChanged() {
        let held = record(previous: 0, acAtWrite: 0)
        #expect(Evaluation.quitStep(record: held, live: live(battery: 2, ac: 0)) == .handBack)
        #expect(Evaluation.quitStep(record: held, live: live(battery: 1, ac: 1)) == .handBack)
        #expect(Evaluation.quitStep(record: held, live: live(battery: 0, ac: 1)) == .handBack)
        #expect(Evaluation.quitStep(record: held, live: live(battery: 1, ac: 0, usesPowermodeKey: false)) == .handBack)
    }

    /// The record a failed engage kept, with the write that never landed: the setting is
    /// still exactly what BatFi found. Nothing to give back, and nothing the user did, so no
    /// hand-back latch for the next launch — the same reading the reconcile gives it.
    @Test func quittingForgetsARecordWhoseSettingIsStillThePreviousOne() {
        let held = record(previous: 0, acAtWrite: 0)
        #expect(Evaluation.quitStep(record: held, live: live(battery: 0, ac: 0)) == .forget)
        #expect(Evaluation.QuitStep.forget.reason == "previousValueInEffect")
    }

    /// Without a reading BatFi does not act blind, and the helper — still armed, still
    /// checking ownership itself — is the one left to give it back as it exits.
    @Test func quittingWithoutAReadingLeavesItToTheHelper() {
        #expect(Evaluation.quitStep(record: record(), live: nil) == .leaveToHelper)
        #expect(Evaluation.quitStep(record: record(), live: live(battery: nil)) == .leaveToHelper)
    }
}

@Suite struct AutoLowPowerModeHelperSessionTests {
    @Test func aFreshSessionAsksAndReconciles() {
        let session = AutoLowPowerModeHelperSession()
        #expect(session.mayAsk)
        #expect(session.needsReconcile)
    }

    private let slow = AutoLowPowerModeHelperSession.slowAnswer
    private let quick = Duration.milliseconds(40)

    /// An older helper stalls on the new calls until the watchdog tears the shared connection
    /// down, failing whatever else was in flight. So one slow "unknown" is enough to stop
    /// asking — until a helper next becomes healthy, which is what an upgrade or a restart
    /// looks like.
    @Test func aSlowUnknownAnswerStopsTheAskingUntilTheNextHealthyEdge() {
        var session = AutoLowPowerModeHelperSession()
        session.helperAnsweredUnknown(at: session.mark, after: slow)
        #expect(!session.mayAsk)
        session.helperBecameHealthy()
        #expect(session.mayAsk)
    }

    @Test func theSlowThresholdIsTenSeconds() {
        #expect(AutoLowPowerModeHelperSession.slowAnswer == .seconds(10))
        var atThreshold = AutoLowPowerModeHelperSession()
        atThreshold.helperAnsweredUnknown(at: atThreshold.mark, after: .seconds(10))
        #expect(!atThreshold.mayAsk)
        var justUnder = AutoLowPowerModeHelperSession()
        justUnder.helperAnsweredUnknown(at: justUnder.mark, after: .milliseconds(9_999))
        #expect(justUnder.mayAsk)
    }

    /// A quick "unknown" is a helper that answered — `pmset` failed this once, say — and
    /// asking it again on the next trigger costs nothing.
    @Test func aQuickUnknownAnswerKeepsAsking() {
        var session = AutoLowPowerModeHelperSession()
        session.helperAnsweredUnknown(at: session.mark, after: quick)
        #expect(session.mayAsk)
    }

    @Test func aReconcileIsOwedAgainOnEveryHealthyEdge() {
        var session = AutoLowPowerModeHelperSession()
        session.reconciled(at: session.mark)
        #expect(!session.needsReconcile)
        session.helperBecameHealthy()
        #expect(session.needsReconcile)
        session.reconciled(at: session.mark)
        #expect(!session.needsReconcile)
    }

    /// A helper that exits and is started again on the next call never leaves "healthy": one
    /// dropped connection is followed by a ping that succeeds. The dropped connection is the
    /// only sign, and the new process restored the value on its way out and has nothing
    /// armed — so it is owed a reconcile all the same.
    @Test func aLostConnectionOwesAReconcile() {
        var session = AutoLowPowerModeHelperSession()
        session.reconciled(at: session.mark)
        session.connectionWasLost()
        #expect(session.needsReconcile)
    }

    /// But it does not lift the stop on asking. Only a healthy edge does, so a helper that
    /// cannot answer is not asked again on every dropped connection.
    @Test func aLostConnectionDoesNotResumeTheAsking() {
        var session = AutoLowPowerModeHelperSession()
        session.helperAnsweredUnknown(at: session.mark, after: slow)
        session.connectionWasLost()
        #expect(!session.mayAsk)
    }

    /// An evaluation that began before the helper came back must not speak for the new one:
    /// its "unknown" was the old helper's, and its reconcile was against the old process.
    @Test func answersFromBeforeAHealthyEdgeAreIgnored() {
        var session = AutoLowPowerModeHelperSession()
        let started = session.mark
        session.helperBecameHealthy()
        session.helperAnsweredUnknown(at: started, after: slow)
        session.reconciled(at: started)
        #expect(session.mayAsk)
        #expect(session.needsReconcile)
    }

    @Test func aReconcileFromBeforeALostConnectionIsIgnored() {
        var session = AutoLowPowerModeHelperSession()
        let started = session.mark
        session.connectionWasLost()
        session.reconciled(at: started)
        #expect(session.needsReconcile)
    }

    /// A write that failed may still have landed — the reply is what was lost — so the record
    /// is kept and the next reading settles it.
    @Test func aWriteThatMayHaveLandedOwesAReconcileAndKeepsAsking() {
        var session = AutoLowPowerModeHelperSession()
        session.reconciled(at: session.mark)
        session.writeMayHaveLanded()
        #expect(session.needsReconcile)
        #expect(session.mayAsk)
    }

    /// The asking is about the helper, not the connection: an "unknown" from the same helper
    /// still counts after a dropped connection.
    @Test func anUnknownFromBeforeALostConnectionStillStopsTheAsking() {
        var session = AutoLowPowerModeHelperSession()
        let started = session.mark
        session.connectionWasLost()
        session.helperAnsweredUnknown(at: started, after: slow)
        #expect(!session.mayAsk)
    }
}
