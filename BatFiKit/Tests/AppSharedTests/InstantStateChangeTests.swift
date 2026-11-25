//
//  InstantStateChangeTests.swift
//  BatFi
//
//  Every change of state is shown the moment it is asked for.
//
//  Under Apple's charge limit powerd adopts a new limit ~40–45 s after it is written, and
//  current takes ~25 s more to start or stop, with IOKit ~20 s behind that. The app used to
//  say so — "Pausing charging…", "Resuming charging…", "Starting charging…" — and the owner,
//  having tried it, wants the opposite: the state the user asked for is shown at once, the
//  way "Charge to 100%" always drew the bolt on the click, and held through the window in
//  which the readings still describe the old limit. One banner, right away; nothing when
//  reality catches up.
//

import Foundation
import L10n
import Shared
import Testing

@testable import AppShared

@Suite struct InstantStateChangeTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: - Inhibit Charging is paused on the click

    private let inhibit = UserTempChargingMode(limit: 85, isInhibit: true)

    private func armed(_ mode: ChargingMode, chargerConnected: Bool = true) -> AppChargingMode {
        AppChargingMode(mode: mode, userTempOverride: inhibit, chargerConnected: chargerConnected)
    }

    /// Whatever the mode underneath — `.charging` until the pass after the click, or for as
    /// long as a sub-80 apply waits on powerd — an armed inhibit is a pause.
    @Test func anArmedInhibitIsPausedWhateverTheMode() {
        for mode in [ChargingMode.charging, .inhibit] {
            #expect(ManualInhibit.pausedLimit(of: armed(mode)) == 85)
            #expect(armed(mode).stateDescription == L10n.AppChargingMode.State.Title.chargingPausedAt("85%"))
            #expect(armed(mode).stateDescription(chargeLimitFraction: 0.9) == L10n.AppChargingMode.State.Description.chargingPaused)
        }
    }

    @Test func anArmedInhibitDrawsThePlug() {
        #expect(BatteryIndicatorMode(appChargingMode: armed(.charging)) == .inhibited)
        #expect(BatteryIndicatorMode(appChargingMode: armed(.inhibit)) == .inhibited)
    }

    @Test func anArmedInhibitIsAnnouncedAtOnce() {
        #expect(ModeChangeAnnouncement.consideration(of: armed(.charging), manageCharging: true) == .announce)
    }

    @Test func aPlainOverrideHasNoPause() {
        let plain = AppChargingMode(mode: .charging, userTempOverride: UserTempChargingMode(limit: 85), chargerConnected: true)
        #expect(ManualInhibit.pausedLimit(of: plain) == nil)
        #expect(BatteryIndicatorMode(appChargingMode: plain) == .charging)
    }

    @Test func anUnpluggedInhibitIsNotAPause() {
        #expect(ManualInhibit.pausedLimit(of: armed(.charging, chargerConnected: false)) == nil)
        #expect(BatteryIndicatorMode(appChargingMode: armed(.charging, chargerConnected: false)) == .discharging)
    }

    // MARK: - Charging ahead of a slow apply

    private func chargesAhead(
        backend: ChargeBackend? = .systemChargeLimit,
        chargerConnected: Bool = true,
        lastApplied: Int? = 80,
        requested: Int = 100,
        level: Int = 80,
        override: UserTempChargingMode? = nil,
        passIsStale: Bool = false,
        appliesAreFailing: Bool = false
    ) -> Bool {
        modeAhead(backend: backend, chargerConnected: chargerConnected, lastApplied: lastApplied, requested: requested, level: level, override: override, passIsStale: passIsStale, appliesAreFailing: appliesAreFailing) == .charging
    }

    private func modeAhead(
        backend: ChargeBackend? = .systemChargeLimit,
        chargerConnected: Bool = true,
        lastApplied: Int? = 80,
        requested: Int = 100,
        floor: Int? = nil,
        level: Int = 80,
        override: UserTempChargingMode? = nil,
        passIsStale: Bool = false,
        appliesAreFailing: Bool = false
    ) -> ChargingMode? {
        ChargingAheadOfApply.modeAhead(
            backend: backend,
            chargerConnected: chargerConnected,
            lastApplied: lastApplied,
            requested: requested,
            floor: floor,
            batteryLevel: level,
            overrideInForce: override,
            passIsStale: passIsStale,
            appliesAreFailing: appliesAreFailing
        )
    }

    /// A raise over a battery below it charges before the apply, which can wait up to 45 s
    /// for powerd on macOS 27 — the bolt and "Charging to the limit" from the first pass.
    @Test func aRaiseOverABatteryBelowItChargesAheadOfTheApply() {
        #expect(chargesAhead())
        #expect(chargesAhead(lastApplied: 60, requested: 70, level: 62))
    }

    /// Before macOS 27 the floor is 80: a 70 request over an applied 80 is no raise.
    @Test func aRequestUnderTheAppliedFloorDoesNotChargeAhead() {
        #expect(!chargesAhead(lastApplied: 80, requested: 70, level: 65))
        #expect(!chargesAhead(lastApplied: 80, requested: 80, level: 65))
    }

    @Test func aRaiseUnderTheBatteryDoesNotChargeAhead() {
        #expect(!chargesAhead(requested: 90, level: 90))
    }

    @Test func noAppliedLimitYetDoesNotChargeAhead() {
        #expect(!chargesAhead(lastApplied: nil))
    }

    @Test func onlyAppleChargeLimitChargesAhead() {
        #expect(!chargesAhead(backend: .chte))
        #expect(!chargesAhead(backend: .legacyCH0BC))
        #expect(!chargesAhead(backend: nil))
    }

    @Test func nothingChargesAheadOffTheCharger() {
        #expect(!chargesAhead(chargerConnected: false))
    }

    /// An inhibit is a pause, never a charge.
    @Test func anInhibitDoesNotChargeAhead() {
        #expect(!chargesAhead(override: UserTempChargingMode(limit: 100, isInhibit: true)))
    }

    /// A pass that read the override before a click is not asked for anything any more: a
    /// "Charge to 100%" read before Stop Override must not start a charge after it.
    @Test func aStalePassDoesNotChargeAhead() {
        #expect(!chargesAhead(passIsStale: true))
    }

    /// While applies fail, a raise is not known to land.
    @Test func failingAppliesDoNotChargeAhead() {
        #expect(!chargesAhead(appliesAreFailing: true))
    }

    // MARK: - Holding ahead of a slow apply

    /// The slider moved from 75 to 70 on macOS 27 over a battery at 73 and charging: the
    /// apply waits up to 45 s for powerd, and the menu showed charging for all of it.
    @Test func aLoweringUnderTheBatteryHoldsAheadOfTheApply() {
        #expect(modeAhead(lastApplied: 75, requested: 70, level: 73) == .inhibit)
        #expect(modeAhead(lastApplied: 90, requested: 80, level: 80) == .inhibit)
    }

    /// An inhibit's frozen limit is a lowering like any other.
    @Test func anInhibitHoldsAheadOfTheApply() {
        #expect(modeAhead(lastApplied: 80, requested: 65, level: 65, override: UserTempChargingMode(limit: 65, isInhibit: true)) == .inhibit)
    }

    /// A lowering above the battery leaves it charging; nothing to show ahead.
    @Test func aLoweringAboveTheBatteryShowsNothingAhead() {
        #expect(modeAhead(lastApplied: 90, requested: 80, level: 70) == nil)
    }

    /// Where the floor is 80, a 70 request resolves to the 80 already applied: there is no
    /// hold at 70 to show, and a battery at 75 goes on charging to 80.
    @Test func aRequestUnderTheFloorIsJudgedAtTheFloor() {
        #expect(modeAhead(lastApplied: 80, requested: 70, floor: 80, level: 75) == nil)
        #expect(modeAhead(lastApplied: 90, requested: 70, floor: 80, level: 85) == .inhibit)
        #expect(modeAhead(lastApplied: 90, requested: 70, floor: 80, level: 75) == nil)
        #expect(modeAhead(lastApplied: 80, requested: 70, floor: 80, level: 75) != .charging)
    }

    /// A plain override below the battery is a discharge, BatFi's own, decided after the apply.
    @Test func aPlainOverrideLoweringShowsNothingAhead() {
        #expect(modeAhead(lastApplied: 80, requested: 50, level: 60, override: UserTempChargingMode(limit: 50)) == nil)
    }

    @Test func aLoweringIsHeldAheadOnlyOnAppleChargeLimit() {
        #expect(modeAhead(backend: .chte, lastApplied: 90, requested: 80, level: 85) == nil)
        #expect(modeAhead(backend: nil, lastApplied: 90, requested: 80, level: 85) == nil)
    }

    @Test func aLoweringIsNotHeldAheadByAStaleOrFailingPass() {
        #expect(modeAhead(lastApplied: 90, requested: 80, level: 85, passIsStale: true) == nil)
        #expect(modeAhead(lastApplied: 90, requested: 80, level: 85, appliesAreFailing: true) == nil)
        #expect(modeAhead(chargerConnected: false, lastApplied: 90, requested: 80, level: 85) == nil)
    }

    // MARK: - Resume Charging at the click

    /// "Resume Charging" under Apple's charge limit is published as charging with the end of
    /// the override, when the battery is below the limit it resumes to: no moment of the
    /// left-over "Inhibiting charging" to show or announce.
    @Test func resumingBelowTheResumedLimitIsChargingAtTheClick() {
        let paused = UserTempChargingMode(limit: 65, isInhibit: true)
        #expect(ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: true, batteryLevel: 65, resumedLimit: 80)).mode == .charging)
    }

    /// Above the limit it resumes to, macOS drains to it: shown at once, as the drain.
    @Test func resumingAboveTheResumedLimitIsTheDrainAtTheClick() {
        let paused = UserTempChargingMode(limit: 85, isInhibit: true)
        let end = ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: true, batteryLevel: 85, resumedLimit: 80))
        #expect(end == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
    }

    /// The inhibit backends are shown at the click too (`ResumeConditions`); a plain override,
    /// and the charger out, publish nothing ahead.
    @Test func onlyAPauseOnTheChargerIsPublishedAtTheClick() {
        let paused = UserTempChargingMode(limit: 65, isInhibit: true)
        #expect(ChargingAheadOfApply.onEndingOverride(UserTempChargingMode(limit: 100), restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: true, batteryLevel: 65, resumedLimit: 80)).mode == nil)
        #expect(ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .chte, chargerConnected: true, batteryLevel: 65, resumedLimit: 80)).mode == .charging)
        #expect(ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: false, batteryLevel: 65, resumedLimit: 80)).mode == nil)
    }

    // MARK: - What an apply will put in force

    /// From 80 up the helper reports the request back as applied (`SMCService.applyChargeLimit`),
    /// and the mode decision after the apply judges the battery against that, so the request
    /// is what is judged ahead of it too; a floor never applies there.
    @Test func aRequestFromEightyUpIsJudgedAsAsked() {
        #expect(ChargingAheadOfApply.willApply(requested: 87, floor: nil) == 87)
        #expect(ChargingAheadOfApply.willApply(requested: 87, floor: 80) == 87)
        #expect(ChargingAheadOfApply.willApply(requested: 100, floor: 80) == 100)
    }

    @Test func aRequestUnderEightyIsJudgedAtTheFloorIfThereIsOne() {
        #expect(ChargingAheadOfApply.willApply(requested: 70, floor: nil) == 70)
        #expect(ChargingAheadOfApply.willApply(requested: 70, floor: 80) == 80)
    }

    /// The floor is learned only from a request below 80. Rounding from 80 up — 87 applied as
    /// 90 — is no floor: learned as one, a later 90-to-75 lowering at 82% showed nothing.
    @Test func theFloorIsLearnedOnlyFromRequestsUnderEighty() {
        #expect(ChargingAheadOfApply.learnedFloor(previous: nil, requested: 87, applied: 90) == nil)
        #expect(ChargingAheadOfApply.learnedFloor(previous: nil, requested: 70, applied: 80) == 80)
        #expect(ChargingAheadOfApply.learnedFloor(previous: 80, requested: 87, applied: 90) == 80)
        #expect(ChargingAheadOfApply.learnedFloor(previous: 80, requested: 90, applied: 90) == 80)
    }

    /// A sub-80 request applied as asked: there is no floor.
    @Test func aSubEightyRequestAppliedAsAskedClearsTheFloor() {
        #expect(ChargingAheadOfApply.learnedFloor(previous: 80, requested: 70, applied: 70) == nil)
    }

    // MARK: - A failing inhibit write

    private let pause = UserTempChargingMode(limit: 77, isInhibit: true)

    /// One failed write is retried by the next pass, as it always was; the pause is kept.
    @Test func oneFailedInhibitWriteKeepsThePause() {
        var failures = InhibitWriteFailures()
        #expect(failures.record(succeeded: false, for: pause) == false)
    }

    /// A write that keeps failing ends the pause rather than claiming it over a charge.
    @Test func aWriteThatKeepsFailingEndsThePause() {
        var failures = InhibitWriteFailures()
        #expect(failures.record(succeeded: false, for: pause) == false)
        #expect(failures.record(succeeded: false, for: pause) == false)
        #expect(failures.record(succeeded: false, for: pause) == true)
        #expect(InhibitWriteFailures.threshold == 3)
    }

    @Test func aWriteThatLandsResetsTheRun() {
        var failures = InhibitWriteFailures()
        _ = failures.record(succeeded: false, for: pause)
        _ = failures.record(succeeded: false, for: pause)
        #expect(failures.record(succeeded: true, for: pause) == false)
        #expect(failures.record(succeeded: false, for: pause) == false)
    }

    /// A new pause starts its own run.
    @Test func aNewPauseStartsItsOwnRun() {
        var failures = InhibitWriteFailures()
        _ = failures.record(succeeded: false, for: pause)
        _ = failures.record(succeeded: false, for: pause)
        #expect(failures.record(succeeded: false, for: UserTempChargingMode(limit: 78, isInhibit: true)) == false)
    }

    // MARK: - Ending only the override being ended

    /// "Charge to 100%" clicked while the Resume before it was still working out its mode:
    /// the end of the pause must not clear the override that replaced it.
    @Test func endingAnOverrideNoLongerInForceChangesNothing() {
        let state = AppChargingMode(mode: .charging, userTempOverride: UserTempChargingMode(limit: 100), chargerConnected: true)
        #expect(state.endingOverride(UserTempChargingMode(limit: 65, isInhibit: true), mode: .charging) == state)
    }

    @Test func endingTheOverrideInForceClearsIt() {
        let paused = UserTempChargingMode(limit: 65, isInhibit: true)
        let state = AppChargingMode(mode: .inhibit, userTempOverride: paused, chargerConnected: true)
        let ended = state.endingOverride(paused, mode: .charging)
        #expect(ended.userTempOverride == nil)
        #expect(ended.mode == .charging)
        #expect(state.endingOverride(paused, mode: nil).mode == .inhibit)
        #expect(state.endingOverride(paused, mode: nil).userTempOverride == nil)
    }

    @Test func endingAnOverrideWithAModeCarriesEverythingElse() {
        let state = AppChargingMode(mode: .inhibit, userTempOverride: UserTempChargingMode(limit: 65, isInhibit: true), chargerConnected: true, isHoldingFullChargeUntilUnplugged: true)
        let next = state.replacingOverride(nil, mode: .charging)
        #expect(next.userTempOverride == nil)
        #expect(next.mode == .charging)
        #expect(next.chargerConnected)
        #expect(next.isHoldingFullChargeUntilUnplugged)
    }

    // MARK: - Holding the state through a lowering

    /// powerd still enforcing the higher limit: a battery charging above the new one is the
    /// old limit, not macOS charging past the new one.
    @Test func aLoweringNotYetAdoptedSuppressesTheAboveLimitStates() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 90, applied: 90, now: at(0))
        #expect(window.record(enforced: 90, applied: 85, now: at(1)).suppressesAboveLimitStates)
        #expect(window.record(enforced: 90, applied: 85, now: at(40)).suppressesAboveLimitStates)
    }

    /// And for the settle interval after powerd adopts it: current takes ~25 s to stop, and
    /// IOKit ~20 s more to say so.
    @Test func anAdoptedLoweringSettlesBeforeTheAboveLimitStatesShow() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 90, applied: 90, now: at(0))
        _ = window.record(enforced: 90, applied: 85, now: at(1))
        #expect(window.record(enforced: 85, applied: 85, now: at(45)).suppressesAboveLimitStates)
        #expect(window.record(enforced: 85, applied: 85, now: at(45 + ChargeLimitRaiseWindow.settleInterval - 1)).suppressesAboveLimitStates)
        #expect(window.record(enforced: 85, applied: 85, now: at(45 + ChargeLimitRaiseWindow.settleInterval)).suppressesAboveLimitStates == false)
    }

    /// A powerd that never adopts the lowering — an off-step value it rounds up, say — is not
    /// waited on for good.
    @Test func aLoweringIsHeldNoLongerThanTheBackstop() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 90, applied: 90, now: at(0))
        _ = window.record(enforced: 90, applied: 87, now: at(1))
        #expect(window.record(enforced: 90, applied: 87, now: at(ChargeLimitRaiseWindow.backstop)).suppressesAboveLimitStates)
        #expect(window.record(enforced: 90, applied: 87, now: at(1 + ChargeLimitRaiseWindow.backstop)).suppressesAboveLimitStates == false)
        #expect(window.record(enforced: 90, applied: 87, now: at(300)).suppressesAboveLimitStates == false)
    }

    /// On the inhibit backends nothing waits on powerd: a lowering opens no window, and the
    /// drift run is not reset for 90 s after every one.
    @Test func aLoweringOpensNoWindowWhereNothingAwaitsPowerd() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: nil, applied: 90, changesAwaitPowerd: false, now: at(0))
        #expect(window.record(enforced: nil, applied: 85, changesAwaitPowerd: false, now: at(1)).suppressesAboveLimitStates == false)
    }

    /// A further raise after a raise powerd never adopted gets its own window: kept from the
    /// first, it had none, and the battery read as held below the limit at once.
    @Test func aFurtherRaiseRestartsTheRaiseWindow() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 80, applied: 80, now: at(0))
        _ = window.record(enforced: 80, applied: 85, now: at(1))
        #expect(window.record(enforced: 80, applied: 85, now: at(200)).suppressesHold == false)
        #expect(window.record(enforced: 80, applied: 90, now: at(210)).suppressesHold)
        #expect(window.record(enforced: 80, applied: 90, now: at(210 + ChargeLimitRaiseWindow.backstop - 1)).suppressesHold)
    }

    @Test func theBackstopIsAboutThreeMinutes() {
        #expect(ChargeLimitRaiseWindow.backstop == 180)
    }

    /// powerd raising its own limit with nothing lowered — calibration's 100 — is not a
    /// lowering, and its top-up shows as it always has.
    @Test func powerdAboveAnUnchangedLimitIsNotALowering() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 80, applied: 80, now: at(0))
        #expect(window.record(enforced: 100, applied: 80, now: at(1)).suppressesAboveLimitStates == false)
    }

    @Test func aFailedApplyIsNotALowering() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 90, applied: 90, now: at(0))
        #expect(window.record(enforced: 90, applied: 70, appliedWasConfirmed: false, now: at(1)).suppressesAboveLimitStates == false)
    }

    /// A raise after a lowering ends the lowering's hold: the battery is below the limit now.
    @Test func aRaiseEndsALoweringsHold() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 90, applied: 90, now: at(0))
        _ = window.record(enforced: 90, applied: 85, now: at(1))
        #expect(window.record(enforced: 90, applied: 95, now: at(5)).suppressesAboveLimitStates == false)
    }

    /// The raise's own hold is capped the same way: a raise powerd never adopts does not
    /// keep "held below the limit" back for good.
    @Test func aRaiseNotAdoptedIsHeldNoLongerThanTheBackstop() {
        var window = ChargeLimitRaiseWindow()
        _ = window.record(enforced: 80, applied: 80, now: at(0))
        #expect(window.record(enforced: 80, applied: 90, now: at(1)).suppressesHold)
        #expect(window.record(enforced: 80, applied: 90, now: at(ChargeLimitRaiseWindow.backstop)).suppressesHold)
        #expect(window.record(enforced: 80, applied: 90, now: at(1 + ChargeLimitRaiseWindow.backstop)).suppressesHold == false)
    }

    // MARK: - End to end

    /// What one simulated pass reads.
    private struct Reading {
        let at: TimeInterval
        let enforced: Int?
        let level: Int
        let isCharging: Bool
        /// The SMC's signed reading; negative is power going into the battery.
        let batteryPower: Float?
    }

    /// The announcer as `NotificationsManager` runs it, with the burst after a click and the
    /// pass after it settling inside one 2 s debounce window.
    private struct Announcer {
        var memory = ModeChangeAnnouncement.Memory()
        var posted: [String] = []
        let limit: Int

        init(limit: Int, baseline: AppChargingMode) {
            self.limit = limit
            // The state before the click, as seen and said.
            settle(baseline)
            posted.removeAll()
        }

        mutating func settle(_ mode: AppChargingMode) {
            switch ModeChangeAnnouncement.consideration(of: mode, manageCharging: true) {
            case .skip:
                memory.skip(mode)
            case .awaitMode:
                break
            case .announce:
                let title = mode.stateDescription
                let body = mode.stateDescription(chargeLimitFraction: Double(limit) / 100) ?? ""
                if memory.decide(.init(mode: mode, limit: limit, automationRuleName: nil), title: title, body: body) == .post {
                    posted.append(title)
                }
            }
        }
    }

    /// One pass of `ChargingManager` under Apple's charge limit, through the rules it applies:
    /// charging ahead of a raise's apply, the raise/lowering window, the above-limit states
    /// (held back while the window says so), the drift run, the held-below verdict and the
    /// mode decision. Returns the published mode.
    private struct Pass {
        var window = ChargeLimitRaiseWindow()
        var latch = SystemChargeTopUpLatch()
        var drift = ChargeHoldDriftMonitor()
        var driftResponses: [ChargeHoldDriftMonitor.Response] = []
        var aboveLimitStatesSeen = false
        var dischargeResumeHold = DischargeResumeHold()

        /// - Parameter snapshot: the override the pass started under, where it differs from
        ///   the one published now; such a pass is stale and publishes no mode.
        mutating func run(
            published: AppChargingMode,
            reading: Reading,
            requested: Int,
            override: UserTempChargingMode?,
            snapshot: UserTempChargingMode?? = .none,
            now: Date,
            onPublish: (AppChargingMode) -> Void
        ) -> AppChargingMode {
            var published = published
            let passOverride = snapshot ?? override
            let isStale = passOverride != published.userTempOverride
            let frozen = passOverride?.isInhibit == true
            // Ahead of the apply.
            if let ahead = ChargingAheadOfApply.modeAhead(
                backend: .systemChargeLimit,
                chargerConnected: true,
                lastApplied: window.lastAppliedLimit,
                requested: requested,
                floor: nil,
                batteryLevel: reading.level,
                overrideInForce: published.userTempOverride,
                passIsStale: isStale,
                appliesAreFailing: false
            ) {
                published = AppChargingMode(
                    mode: ahead,
                    userTempOverride: published.userTempOverride,
                    chargerConnected: true,
                    systemIsDischargingToLimit: ahead == .inhibit && dischargeResumeHold.holdsDrain(batteryLevel: reading.level, limitInForce: requested, overrideInForce: published.userTempOverride)
                )
                onPublish(published)
            }
            let applied = requested
            let verdict = window.record(enforced: reading.enforced, applied: applied, now: now)
            dischargeResumeHold.record(suppressesAboveLimitStates: verdict.suppressesAboveLimitStates, overrideInForce: passOverride, passIsStale: isStale)
            let drainIsHeld = dischargeResumeHold.holdsDrain(batteryLevel: reading.level, limitInForce: applied, overrideInForce: passOverride)
            // The above-limit states, as `systemChargeAboveLimit` works them out.
            var toppingUp = false
            var draining = false
            var snapshotToppingUp = false
            var snapshotDraining = false
            if reading.level > applied {
                if frozen || verdict.suppressesAboveLimitStates {
                    latch.reset()
                    snapshotToppingUp = SystemChargeTopUp.isUnderway(batteryLevel: reading.level, limitInForce: applied, isCharging: reading.isCharging, batteryPower: reading.batteryPower, mechanismDrainsToLimitItself: true)
                    snapshotDraining = SystemChargeDrain.isUnderway(batteryLevel: reading.level, limitInForce: applied, isCharging: reading.isCharging, batteryPower: reading.batteryPower, mechanismDrainsToLimitItself: true)
                } else {
                    let latched = latch.record(chargerConnected: true, batteryLevel: reading.level, limitInForce: applied, isCharging: reading.isCharging, batteryPower: reading.batteryPower, mechanismDrainsToLimitItself: true, at: now)
                    toppingUp = latched.isToppingUp
                    draining = latched.isDraining
                    snapshotToppingUp = latched.snapshotIsToppingUp
                    snapshotDraining = latched.snapshotIsDraining
                }
            }
            // The drift run: not while the window holds the state.
            if verdict.suppressesAboveLimitStates {
                drift = ChargeHoldDriftMonitor()
            } else {
                let drifting = ChargeHoldDrift.isDrifting(
                    chargerConnected: true,
                    isCharging: reading.isCharging,
                    batteryLevel: reading.level,
                    limitInForce: applied,
                    holdIsAttributed: nil,
                    systemIsChargingPastLimit: snapshotToppingUp,
                    systemIsDrainingToLimit: snapshotDraining
                )
                driftResponses.append(drift.record(isDrifting: drifting, at: now))
            }
            // Held below the limit: the attribution as the cache would hand it back, "held".
            let held = !verdict.suppressesHold && SystemChargeHold.isHoldingBelowLimit(
                chargerConnected: true,
                isCharging: reading.isCharging,
                batteryLevel: reading.level,
                limitInForce: applied,
                holdIsAttributed: true,
                chargeIsFlowingIn: ChargeDirection.chargeIsFlowingIn(batteryPower: reading.batteryPower),
                batFiIsDischarging: false,
                mechanismOwnsChargingDecision: true,
                enforcedLimit: reading.enforced
            )
            // The mode decision: none from a stale pass.
            guard !isStale else { return published }
            if override != nil {
                published = AppChargingMode(
                    mode: reading.level < applied ? .charging : .inhibit,
                    userTempOverride: override,
                    chargerConnected: true
                )
            } else if reading.level >= applied {
                if toppingUp || draining { aboveLimitStatesSeen = true }
                published = AppChargingMode(
                    mode: .inhibit,
                    userTempOverride: nil,
                    chargerConnected: true,
                    systemIsDischargingToLimit: draining || drainIsHeld,
                    systemIsChargingPastLimit: toppingUp && !drainIsHeld
                )
            } else {
                published = AppChargingMode(
                    mode: held ? .inhibit : .charging,
                    userTempOverride: nil,
                    chargerConnected: true,
                    systemIsHoldingBelowLimit: held
                )
            }
            onPublish(published)
            return published
        }
    }

    /// "Inhibit Charging" with the battery at 87% charging towards a 90% limit: frozen at 85.
    /// powerd keeps charging under 90 for ~45 s, current stops ~25 s after it adopts 85, and
    /// then macOS drains back to 85.
    ///
    /// Paused, with the plug, from the click; one banner; nothing more when charging stops,
    /// no top-up, no drain, no drift warning.
    @Test func inhibitIsPausedAtOnceAndHeldWhileTheBatteryStillCharges() {
        let readings = [
            Reading(at: 0.2, enforced: 90, level: 87, isCharging: true, batteryPower: -40),
            Reading(at: 10, enforced: 90, level: 87, isCharging: true, batteryPower: -40),
            Reading(at: 30, enforced: 90, level: 88, isCharging: true, batteryPower: -38),
            Reading(at: 45, enforced: 85, level: 88, isCharging: true, batteryPower: -36),
            Reading(at: 60, enforced: 85, level: 88, isCharging: true, batteryPower: -20),
            Reading(at: 75, enforced: 85, level: 88, isCharging: true, batteryPower: 0.3),
            Reading(at: 95, enforced: 85, level: 88, isCharging: false, batteryPower: 8),
            Reading(at: 150, enforced: 85, level: 87, isCharging: false, batteryPower: 8),
            Reading(at: 400, enforced: 85, level: 85, isCharging: false, batteryPower: 0.1),
        ]
        var published = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        var announcer = Announcer(limit: 90, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 90, applied: 90, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        // The click.
        let frozen = HotBatteryHold.frozenLimit(batteryLevel: 87)
        #expect(frozen == 85)
        published = published.replacingOverride(ManualInhibit.override(batteryLevel: 87, backend: .systemChargeLimit))
        look(published)
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: frozen, override: published.userTempOverride, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let paused = L10n.AppChargingMode.State.Title.chargingPausedAt("85%")
        #expect(shown.allSatisfy { $0.0 == paused && $0.1 == .inhibited })
        #expect(announcer.posted == [paused])
        #expect(published.systemIsChargingPastLimit == false)
        #expect(published.systemIsDischargingToLimit == false)
        #expect(pass.driftResponses.allSatisfy { $0 == .none })
    }

    /// "Resume Charging" from a pause at 77% under an 80% limit: charging to the limit from
    /// the first pass, through powerd's ~45 s and the ~45 s before IOKit reports the charge,
    /// in which the battery looks held below the limit. One banner.
    @Test func resumeShowsChargingAtOnceAndHoldsIt() {
        let paused = UserTempChargingMode(limit: 77, isInhibit: true)
        var published = AppChargingMode(mode: .inhibit, userTempOverride: paused, chargerConnected: true)
        var announcer = Announcer(limit: 80, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 77, applied: 77, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        // The click: under Apple's charge limit the end of the pause is published as charging
        // in the same breath, and it is shown and settled like any other publish.
        let clickMode = ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: true, batteryLevel: 77, resumedLimit: 80)).mode
        #expect(clickMode == .charging)
        published = published.replacingOverride(nil, mode: clickMode ?? published.mode)
        look(published)
        announcer.settle(published)
        let readings = [
            Reading(at: 0.2, enforced: 77, level: 77, isCharging: false, batteryPower: 0.1),
            Reading(at: 20, enforced: 77, level: 77, isCharging: false, batteryPower: -0.4),
            Reading(at: 42, enforced: 80, level: 77, isCharging: false, batteryPower: -0.8),
            Reading(at: 68, enforced: 80, level: 77, isCharging: false, batteryPower: -38),
            Reading(at: 90, enforced: 80, level: 78, isCharging: true, batteryPower: -42),
            Reading(at: 300, enforced: 80, level: 79, isCharging: true, batteryPower: -30),
        ]
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 80, override: nil, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let charging = L10n.AppChargingMode.State.Title.charging
        #expect(shown.allSatisfy { $0.0 == charging && $0.1 == .charging })
        #expect(announcer.posted == [charging])
    }

    /// "Charge to 100%" over a battery held at 80: the bolt and the override's own title from
    /// the first pass, and its one banner, though powerd takes ~45 s and current ~25 s more.
    @Test func chargeToFullShowsTheBoltAtOnce() {
        let chargeToFull = UserTempChargingMode(limit: 100)
        var published = AppChargingMode(mode: .inhibit, userTempOverride: nil, chargerConnected: true)
        var announcer = Announcer(limit: 80, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 80, applied: 80, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        published = published.replacingOverride(chargeToFull)
        let readings = [
            Reading(at: 0.2, enforced: 80, level: 80, isCharging: false, batteryPower: 0.1),
            Reading(at: 20, enforced: 80, level: 80, isCharging: false, batteryPower: nil),
            Reading(at: 45, enforced: 100, level: 80, isCharging: false, batteryPower: -0.7),
            Reading(at: 70, enforced: 100, level: 80, isCharging: false, batteryPower: -41),
            Reading(at: 90, enforced: 100, level: 81, isCharging: true, batteryPower: -44),
        ]
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 100, override: chargeToFull, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let override = L10n.AppChargingMode.State.Title.chargeOverride
        #expect(shown.allSatisfy { $0.0 == override && $0.1 == .charging })
        #expect(announcer.posted == [override])
    }

    /// The slider raised from 80 to 90 over a held battery: charging to the limit at once,
    /// one banner, no "Charging paused by macOS" while powerd adopts the raise.
    @Test func aSliderRaiseShowsChargingAtOnce() {
        var published = AppChargingMode(mode: .inhibit, userTempOverride: nil, chargerConnected: true)
        var announcer = Announcer(limit: 90, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 80, applied: 80, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        let readings = [
            Reading(at: 0.1, enforced: 80, level: 80, isCharging: false, batteryPower: 0.2),
            Reading(at: 30, enforced: 80, level: 80, isCharging: false, batteryPower: -0.5),
            Reading(at: 45, enforced: 90, level: 80, isCharging: false, batteryPower: 0),
            Reading(at: 70, enforced: 90, level: 80, isCharging: false, batteryPower: -40),
            Reading(at: 95, enforced: 90, level: 81, isCharging: true, batteryPower: -41),
        ]
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 90, override: nil, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let charging = L10n.AppChargingMode.State.Title.charging
        #expect(shown.allSatisfy { $0.0 == charging && $0.1 == .charging })
        #expect(announcer.posted == [charging])
    }

    /// The slider lowered from 90 to 80 under a battery charging at 85: "Inhibiting charging"
    /// at once, and held while powerd still charges under 90 and current takes its time to
    /// stop — no "macOS is charging past the limit", no drain, no drift run. Once the window
    /// is over macOS's own drain to 80 shows, quietly: it is genuine by then.
    @Test func aSliderLoweringIsHeldWhileTheBatteryStillCharges() {
        var published = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        var announcer = Announcer(limit: 80, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 90, applied: 90, now: start)
        var shown: [(TimeInterval, String)] = []

        let readings = [
            Reading(at: 0.1, enforced: 90, level: 85, isCharging: true, batteryPower: -40),
            Reading(at: 20, enforced: 90, level: 85, isCharging: true, batteryPower: -40),
            Reading(at: 45, enforced: 80, level: 86, isCharging: true, batteryPower: -35),
            Reading(at: 70, enforced: 80, level: 86, isCharging: true, batteryPower: -10),
            Reading(at: 100, enforced: 80, level: 86, isCharging: true, batteryPower: 8),
            Reading(at: 200, enforced: 80, level: 85, isCharging: false, batteryPower: 8),
        ]
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 80, override: nil, now: at(reading.at)) { _ in }
            shown.append((reading.at, published.stateDescription))
            announcer.settle(published)
        }

        let inhibiting = L10n.AppChargingMode.State.Title.inhibit
        #expect(shown.filter { $0.0 < 135 }.allSatisfy { $0.1 == inhibiting })
        #expect(announcer.posted == [inhibiting])
        #expect(pass.driftResponses.allSatisfy { $0 == .none })
        #expect(published.systemIsChargingPastLimit == false)
    }

    /// The slider moved from 75 to 70 on macOS 27 over a battery at 73 and charging. The apply
    /// of a sub-80 limit waits up to 45 s for powerd; the hold is shown ahead of it, with the
    /// plug, and held while the battery charges on. One banner.
    @Test func aSubEightyLoweringIsShownAheadOfTheApply() {
        var published = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        var announcer = Announcer(limit: 70, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 75, applied: 75, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        let readings = [
            // The first pass: shown ahead of an apply that returns ~45 s later.
            Reading(at: 0.1, enforced: 75, level: 73, isCharging: true, batteryPower: -30),
            Reading(at: 46, enforced: 70, level: 74, isCharging: true, batteryPower: -25),
            Reading(at: 70, enforced: 70, level: 74, isCharging: true, batteryPower: -5),
            Reading(at: 100, enforced: 70, level: 74, isCharging: false, batteryPower: 6),
        ]
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 70, override: nil, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let inhibiting = L10n.AppChargingMode.State.Title.inhibit
        #expect(shown.first?.0 == inhibiting)
        #expect(shown.allSatisfy { $0.0 == inhibiting && $0.1 == .inhibited })
        #expect(announcer.posted == [inhibiting])
        #expect(pass.driftResponses.allSatisfy { $0 == .none })
    }

    /// "Inhibit Charging" at 65 and "Resume Charging" within the ~45 s its sub-80 apply waits.
    /// The inhibit's pass comes back from that apply after the resume, still holding the
    /// pause it started under: it publishes nothing, so the plug does not come back over the
    /// charging the resume showed, and no second banner contradicts it.
    @Test func aStalePassDoesNotPublishThePauseBackAfterAResume() {
        let paused = UserTempChargingMode(limit: 65, isInhibit: true)
        var published = AppChargingMode(mode: .charging, userTempOverride: nil, chargerConnected: true)
        var announcer = Announcer(limit: 80, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 80, applied: 80, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        // Inhibit: shown and announced at once; its pass is now suspended in the apply.
        published = published.replacingOverride(paused)
        look(published)
        announcer.settle(published)
        // Resume, 10 s later: charging at the click, and its pass.
        let clickMode = ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: true, batteryLevel: 65, resumedLimit: 80)).mode
        published = published.replacingOverride(nil, mode: clickMode ?? published.mode)
        look(published)
        published = pass.run(published: published, reading: Reading(at: 10, enforced: 80, level: 65, isCharging: true, batteryPower: -30), requested: 80, override: nil, now: at(10), onPublish: look)
        announcer.settle(published)
        // The inhibit's pass returns from its apply, stale.
        published = pass.run(published: published, reading: Reading(at: 45, enforced: 65, level: 65, isCharging: false, batteryPower: 0.1), requested: 65, override: nil, snapshot: .some(paused), now: at(45), onPublish: look)
        announcer.settle(published)
        // The next fresh pass.
        published = pass.run(published: published, reading: Reading(at: 50, enforced: 65, level: 65, isCharging: false, batteryPower: 0.1), requested: 80, override: nil, now: at(50), onPublish: look)
        announcer.settle(published)

        let charging = L10n.AppChargingMode.State.Title.charging
        let pausedTitle = L10n.AppChargingMode.State.Title.chargingPausedAt("65%")
        #expect(Array(shown.dropFirst()).allSatisfy { $0.0 == charging && $0.1 == .charging })
        #expect(announcer.posted == [pausedTitle, charging])
    }

    // MARK: - Pause Discharging, end to end

    /// The owner's case: on the charger at 100%, macOS draining to an 80% limit at ~4 A.
    /// "Pause Discharging" freezes Apple's limit at 100; powerd goes on draining under 80 for
    /// ~45 s and current takes ~25 s more to stop, the battery a point lower by then.
    ///
    /// Paused, with the pause drawn, from the click; one banner; no drain shown again, no
    /// charging, no drift warning.
    @Test func pauseDischargingIsPausedAtOnceAndHeldWhileMacOSStillDrains() {
        let readings = [
            Reading(at: 0.2, enforced: 80, level: 100, isCharging: false, batteryPower: 45),
            Reading(at: 20, enforced: 80, level: 100, isCharging: false, batteryPower: 45),
            Reading(at: 44, enforced: 100, level: 99, isCharging: false, batteryPower: 44),
            Reading(at: 60, enforced: 100, level: 99, isCharging: false, batteryPower: 20),
            Reading(at: 75, enforced: 100, level: 99, isCharging: false, batteryPower: 0.2),
            Reading(at: 200, enforced: 100, level: 99, isCharging: false, batteryPower: 0.1),
        ]
        var published = AppChargingMode(mode: .inhibit, userTempOverride: nil, chargerConnected: true, systemIsDischargingToLimit: true)
        var announcer = Announcer(limit: 80, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 80, applied: 80, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        // The click.
        #expect(StatusMenuCommands.pauseTitle(mode: published, backend: .systemChargeLimit) == L10n.Menu.Label.pauseDischarging)
        let pause = ManualInhibit.pause(for: published, batteryLevel: 100, backend: .systemChargeLimit)
        #expect(pause == UserTempChargingMode(limit: 100, isInhibit: true, pausesDischarge: true))
        published = published.replacingOverride(pause)
        look(published)
        announcer.settle(published)
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 100, override: pause, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let paused = L10n.AppChargingMode.State.Title.dischargingPausedAt("100%")
        #expect(shown.allSatisfy { $0.0 == paused && $0.1 == .inhibited })
        #expect(announcer.posted == [paused])
        #expect(pass.driftResponses.allSatisfy { $0 == .none })
        #expect(StatusMenuCommands.stopOverrideTitle(for: published.userTempOverride!) == L10n.Menu.Label.resumeDischarging)
    }

    /// "Resume Discharging" from a pause at 95% under an 80% limit: macOS draining from the
    /// click, though powerd adopts 80 only after ~45 s and current turns round ~25 s later —
    /// a window in which the drain is held back with the other above-limit states. One banner;
    /// nothing when the drain is measured.
    @Test func resumeDischargingShowsTheDrainAtOnceAndHoldsIt() {
        let paused = UserTempChargingMode(limit: 95, isInhibit: true, pausesDischarge: true)
        var published = AppChargingMode(mode: .inhibit, userTempOverride: paused, chargerConnected: true)
        var announcer = Announcer(limit: 80, baseline: published)
        var pass = Pass()
        _ = pass.window.record(enforced: 95, applied: 95, now: start)
        var shown: [(String, BatteryIndicatorMode)] = []
        func look(_ mode: AppChargingMode) {
            shown.append((mode.stateDescription, BatteryIndicatorMode(appChargingMode: mode)))
        }

        // The click.
        let end = ChargingAheadOfApply.onEndingOverride(paused, restoringPausedOverride: true, conditions: ResumeConditions(backend: .systemChargeLimit, chargerConnected: true, batteryLevel: 95, resumedLimit: 80))
        #expect(end == OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
        pass.dischargeResumeHold.arm()
        published = published.endingOverride(paused, with: end)
        look(published)
        announcer.settle(published)
        let readings = [
            Reading(at: 0.2, enforced: 95, level: 95, isCharging: false, batteryPower: 0.1),
            Reading(at: 20, enforced: 95, level: 95, isCharging: false, batteryPower: 0.1),
            Reading(at: 44, enforced: 80, level: 95, isCharging: false, batteryPower: 0.2),
            Reading(at: 70, enforced: 80, level: 95, isCharging: false, batteryPower: 30),
            Reading(at: 120, enforced: 80, level: 94, isCharging: false, batteryPower: 44),
            Reading(at: 200, enforced: 80, level: 92, isCharging: false, batteryPower: 45),
            Reading(at: 400, enforced: 80, level: 88, isCharging: false, batteryPower: 45),
        ]
        for reading in readings {
            published = pass.run(published: published, reading: reading, requested: 80, override: nil, now: at(reading.at), onPublish: look)
            announcer.settle(published)
        }

        let draining = L10n.AppChargingMode.State.Title.systemDischargingToLimit
        #expect(shown.allSatisfy { $0.0 == draining && $0.1 == .discharging })
        #expect(announcer.posted == [draining])
        #expect(!pass.dischargeResumeHold.isArmed)
    }

    /// The same resume with no hold: the window's plain "Inhibiting charging" and the plug —
    /// what the hold is there to keep off the screen.
    @Test func withoutTheHoldTheResumeWouldShowTheHold() {
        let paused = UserTempChargingMode(limit: 95, isInhibit: true, pausesDischarge: true)
        var published = AppChargingMode(mode: .inhibit, userTempOverride: paused, chargerConnected: true)
        var pass = Pass()
        _ = pass.window.record(enforced: 95, applied: 95, now: start)
        published = published.endingOverride(paused, with: OverrideEnd(mode: .inhibit, systemIsDischargingToLimit: true))
        published = pass.run(published: published, reading: Reading(at: 0.2, enforced: 95, level: 95, isCharging: false, batteryPower: 0.1), requested: 80, override: nil, now: at(0.2)) { _ in }
        #expect(BatteryIndicatorMode(appChargingMode: published) == .inhibited)
    }
}
