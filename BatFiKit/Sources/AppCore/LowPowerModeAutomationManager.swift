//
//  LowPowerModeAutomationManager.swift
//  BatFi
//
//  Turns Low Power Mode on for the battery once the charge drops to the user's threshold,
//  and gives back exactly what it took. What to do is `AutoLowPowerModePolicy`'s call and
//  when to ask the helper is `AutoLowPowerModeEvaluation`'s. This actor makes the calls, in
//  an order that cannot lose track of what BatFi changed.
//
//  Its own manager rather than part of `ChargingManager`, because it has to work with charge
//  management switched off, and not part of the automation engine, which drives the charge
//  limit on a sixty-second cadence. It follows the app licence as charge management does,
//  though: without a valid one it turns nothing on and gives back what it holds.
//

import AppShared
import AsyncAlgorithms
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import L10n
import License
import os
import Shared

public actor LowPowerModeAutomationManager {
    private lazy var logger = Logger(category: "Low Power Mode Automation")
    @Dependency(\.powerModeClient) private var powerModeClient
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.helperHealthClient) private var helperHealthClient
    @Dependency(\.userNotificationsClient) private var userNotificationsClient
    @Dependency(\.defaults) private var defaults
    @Dependency(\.suspendingClock) private var clock
    @Dependency(\.date) private var date

    /// What an evaluation needs to know besides the live setting and the stored record.
    private struct Context: Equatable, Sendable {
        let enabled: Bool
        let threshold: Int
        let onBattery: Bool
        let batteryLevel: Int

        init(enabled: Bool, threshold: Int, powerState: PowerState, appMode: ChargingMode) {
            self.enabled = enabled
            self.threshold = threshold
            // The one answer every feature that acts "on battery" asks, so BatFi's own force
            // discharge counts as being on the charger.
            self.onBattery = ChargerConnection.isOnBattery(
                reported: powerState.chargerConnected,
                isDerived: powerState.chargerConnectionIsDerived,
                appMode: appMode
            )
            self.batteryLevel = powerState.batteryLevel
        }
    }

    /// Whether `setUpObserving()` has already run.
    private var isObserving = false
    /// Set by `appWillQuit()`: from then on the quit path owns the record, and no evaluation
    /// may start or engage.
    private var isQuitting = false
    /// The latest settings and power state, as the main observation loop last delivered
    /// them. Nil until it has delivered once; nothing is evaluated before that.
    private var context: Context?
    private var unlockModel: UnlockModel?
    /// The licence, or a running trial, as the unlock model last reported it. Unknown until
    /// both have been read: see `LicenseStatus`.
    private var license: LicenseStatus = .unknown
    private var session = AutoLowPowerModeHelperSession()
    /// The evaluation running now, so that quitting can let it finish first.
    private var inFlight: Task<Void, Never>?
    /// Wakes an evaluation every sixty seconds while a record is held — the one way to notice
    /// a change nothing announces, such as the AC half of the setting being changed in
    /// System Settings while the Mac runs on its battery.
    private var tick: Task<Void, Never>?

    /// Every trigger ends up here, and one consumer drains it, so evaluations never overlap.
    ///
    /// They must not: an evaluation awaits the helper between reading the live setting and
    /// writing it, and the actor is reentrant. A second evaluation interleaved into an
    /// engage would find the record stored and the write not yet landed, read that as the
    /// user having changed the setting, and hand back a Low Power Mode that the first then
    /// turns on — with no record left to give it back.
    ///
    /// A trigger carries nothing, since each evaluation starts from the state as it is then,
    /// so the buffer keeps only the newest: however many arrive during one evaluation, one
    /// more follows it.
    private let triggers: AsyncStream<Void>
    private let trigger: AsyncStream<Void>.Continuation

    public init() {
        (triggers, trigger) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Before `setUpObserving()`, as for `ChargingManager`.
    public func setUnlockModel(_ unlockModel: UnlockModel) {
        self.unlockModel = unlockModel
    }

    public func setUpObserving() {
        // Once only, for the reason `MagSafeColorManager.setUpObserving()` gives: the tasks
        // below are never retained, and `setUpTheApp()` is reached from two places.
        guard !isObserving else { return }
        isObserving = true

        Task {
            for await _ in triggers {
                let evaluation = Task { await self.evaluate() }
                inFlight = evaluation
                await evaluation.value
                inFlight = nil
            }
        }

        // Deduplicated before the debounce, so that the power source's frequent updates of
        // things this does not read — time remaining, temperature — neither evaluate nor
        // hold back a change that matters.
        Task {
            for await context in combineLatest(
                combineLatest(
                    defaults.observe(.autoLowPowerModeEnabled),
                    defaults.observe(.autoLowPowerModeThreshold)
                ),
                combineLatest(
                    powerSourceClient.powerSourceChanges(),
                    appChargingState.appChargingModeDidChage()
                )
            )
            .map({ @Sendable element in
                Context(
                    enabled: element.0.0,
                    threshold: element.0.1,
                    powerState: element.1.0,
                    appMode: element.1.1.mode
                )
            })
            .removeDuplicates()
            .debounce(for: .seconds(1), clock: AnyClock(self.clock))
            {
                contextDidChange(context)
            }
        }

        // The licence, read at once rather than on the next change or tick: losing it gives
        // Low Power Mode back, and activating one turns it on with no relaunch. The model's
        // stream starts with the state it is in.
        if let unlockModel {
            Task {
                for await status in await unlockModel.statusChanges() {
                    licenseDidChange(status)
                }
            }
        } else {
            logger.error("No unlock model; automatic Low Power Mode turns nothing on")
            assertionFailure("setUnlockModel(_:) must be called before setUpObserving()")
        }

        // Low Power Mode going on or off, whoever did it.
        let lowPowerModeChanges = powerModeClient.lowPowerModeActiveChanges()
        Task {
            for await _ in lowPowerModeChanges {
                trigger.yield()
            }
        }

        // A write through BatFi's own client — the manual toggle and hotkeys, which change
        // the AC half too, and this feature's own writes. Detached because `Notification` is
        // not Sendable and must not be handed across into the actor.
        let trigger = self.trigger
        Task.detached {
            for await _ in NotificationCenter.default.notifications(named: .powerModeDidChange) {
                trigger.yield()
            }
        }

        // The helper coming back. It restored the value on its way out and has nothing armed,
        // so it is owed a reconcile and a re-arm; and if it could not answer before, it is
        // given the chance again.
        let health = helperHealthClient.observeHealth()
        Task {
            var wasHealthy = false
            for await state in health {
                defer { wasHealthy = state.isHealthy }
                guard state.isHealthy, !wasHealthy else { continue }
                helperBecameHealthy()
            }
        }

        // The other sign of a helper exit, and the only one when the next call starts a new
        // helper at once: see `AutoLowPowerModeHelperSession`. It owes a reconcile but does
        // not evaluate by itself. While the helper cannot be reached, every evaluation that
        // asks it opens a connection that drops again, so evaluating here would feed itself;
        // the next trigger does it instead — within a minute while a record is held.
        let connectionFailures = helperHealthClient.observeConnectionFailures()
        Task {
            for await _ in connectionFailures {
                session.connectionWasLost()
            }
        }
    }

    /// Gives Low Power Mode back if BatFi still holds it, so that it does not stay on with no
    /// BatFi running to give it back on the charger. Leaves the helper disarmed wherever the
    /// record is settled, so that its own restore is not left to run inside `quitHelper()`,
    /// and armed with the record wherever it stays held, so that the helper gives the value
    /// back as it exits.
    ///
    /// Asks the helper nothing unless a record is held. Against a helper too old to know the
    /// call, a read stalls for fifteen seconds — longer than the app's own ten-second
    /// terminate fallback — and `quitHelper()` would never be sent.
    public func appWillQuit() async {
        isQuitting = true
        tick?.cancel()
        tick = nil
        // Checked before waiting on anything. With no record there is nothing to give back,
        // and nothing can create one from here on: an engage stores its record before its
        // first suspension, and none starts once `isQuitting` is set.
        guard defaults.value(.autoLowPowerModeRecord) != nil else { return }
        if let inFlight {
            // Bounded, because the evaluation may be waiting on the helper itself.
            let finished = await waitAtMost(.seconds(3)) { await inFlight.value }
            guard finished else {
                // Most likely an engage whose write has not come back, so what the setting
                // is now cannot be known and acting on a reading would race it. The record
                // stays for the next launch to reconcile.
                logger.warning("An automatic Low Power Mode evaluation was still running at quit; keeping the record for the next launch")
                return
            }
        }
        // Read again: the evaluation just waited on may have given it back already.
        guard let record = defaults.value(.autoLowPowerModeRecord) else { return }
        guard session.mayAsk else {
            logger.notice("Quitting with Low Power Mode held and a helper that could not report it; not asking it again. It gives Low Power Mode back as it exits if it was armed, and the next launch reconciles the record")
            return
        }
        let key = PowerModeBySource.pmsetKey(usesPowermodeKey: record.usesPowermodeKey)
        let asked = session.mark
        var live: PowerModeBySource?
        // Timed, as every read is, so that a slow "unknown" stops the asking here too: the
        // helper is not then asked to arm.
        let elapsed = await clock.measure {
            live = await powerModeClient.powerModeBySource()
        }
        if live?.battery == nil {
            session.helperAnsweredUnknown(at: asked, after: elapsed)
        }
        let step = AutoLowPowerModeEvaluation.quitStep(record: record, live: live)
        switch step {
        case .restore:
            do {
                try await powerModeClient.setBatteryPowerMode(record.previousBatteryValue, record.usesPowermodeKey)
            } catch {
                // The record stays for the next launch to reconcile, and the helper is armed:
                // it is the last thing left that can give the value back tonight.
                logger.error("Could not give Low Power Mode back at quit (\(step.reason, privacy: .public)): \(error, privacy: .public)")
                await leaveToHelper(record)
                return
            }
            defaults.setValue(.autoLowPowerModeRecord, value: nil)
            logger.notice("Gave Low Power Mode back at quit: battery \(key, privacy: .public) is \(record.previousBatteryValue, privacy: .public) again (\(step.reason, privacy: .public))")
            await armHelper(with: nil)
        case .forget:
            defaults.setValue(.autoLowPowerModeRecord, value: nil)
            logger.notice("Low Power Mode is already what BatFi found; forgetting the record at quit (\(step.reason, privacy: .public))")
            await armHelper(with: nil)
        case .handBack:
            defaults.setValue(.autoLowPowerModeRecord, value: nil)
            if let context { storeLatch(context.onBattery) }
            logger.notice("Low Power Mode was changed since BatFi turned it on; leaving it to the user at quit (\(step.reason, privacy: .public))")
            await armHelper(with: nil)
        case .leaveToHelper:
            logger.notice("Could not read Low Power Mode at quit (\(step.reason, privacy: .public))")
            await leaveToHelper(record)
        }
    }

    /// Arms the helper with the record a quit leaves held, so that the helper gives the value
    /// back as it exits — the last thing left that can, with BatFi gone.
    ///
    /// The helper may not hold it: an engage whose write failed keeps its record without
    /// arming, and an arm can fail. Arming again is harmless. Not a helper whose read just
    /// stalled, though: asking it anything more stalls the quit again, and `quitHelper()`
    /// behind it, which the ten-second terminate fallback would then cut short.
    private func leaveToHelper(_ record: AutoLowPowerModeRecord) async {
        guard session.mayAsk else {
            logger.notice("Not asking a helper that could not report Low Power Mode to give it back as it exits; the next launch reconciles the record")
            return
        }
        logger.notice("Leaving the helper armed to give Low Power Mode back as it exits")
        await armHelper(with: record)
    }

    // MARK: - Triggers

    private func contextDidChange(_ context: Context) {
        self.context = context
        trigger.yield()
    }

    /// Evaluates at once, and says so once per change. A record an earlier run left is kept
    /// while the licence is being read at launch, and given back only once it reads not
    /// valid; see `AutoLowPowerModePolicy.Input.license`.
    private func licenseDidChange(_ next: LicenseStatus) {
        guard next != license else { return }
        license = next
        switch next {
        case .valid:
            logger.notice("Licence active — automatic Low Power Mode may turn Low Power Mode on")
        case .invalid:
            logger.notice("Licence not active — automatic Low Power Mode turns nothing on, and gives back Low Power Mode if BatFi turned it on")
        case .unknown:
            break
        }
        trigger.yield()
    }

    private func helperBecameHealthy() {
        session.helperBecameHealthy()
        logger.debug("Helper is reachable; automatic Low Power Mode reconciles against it")
        trigger.yield()
    }

    /// Runs the tick while a record is held, and only then.
    private func updateTick() {
        let holding = defaults.value(.autoLowPowerModeRecord) != nil
        if holding, !isQuitting, tick == nil {
            let trigger = self.trigger
            let clock = self.clock
            tick = Task {
                while true {
                    do {
                        try await clock.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    trigger.yield()
                }
            }
        } else if !holding || isQuitting, let running = tick {
            running.cancel()
            tick = nil
        }
    }

    // MARK: - Evaluation

    private func evaluate() async {
        guard !isQuitting, let context else { return }
        // First, and whatever the helper answers: being on the charger ends the discharge,
        // and with it the once the notification is posted in — and so does a level where
        // the policy gives Low Power Mode back, as after a charge BatFi did not see.
        updateAnnouncement(engaged: false, context: context)
        let asked = session.mark
        var input = AutoLowPowerModePolicy.Input(
            enabled: context.enabled,
            license: license,
            threshold: context.threshold,
            onBattery: context.onBattery,
            batteryLevel: context.batteryLevel,
            live: nil,
            record: defaults.value(.autoLowPowerModeRecord),
            yieldedUntilCharge: defaults.value(.autoLowPowerModeYieldedUntilCharge),
            now: date.now
        )
        // Without a reading the policy still runs: it writes nothing blind, and it still
        // resets the hand-back latch once the Mac is on the charger.
        if session.mayAsk, AutoLowPowerModeEvaluation.needsLiveState(input) {
            // Same stand-down as `ChargingManager`: while the app is taking the daemon down
            // to reclaim it, every call fails, and a write could land on the other copy's
            // helper. The healthy edge that ends it evaluates again.
            guard await !helperHealthClient.isReclaimingHelper() else {
                logger.debug("Reclaiming the helper; automatic Low Power Mode waits for it")
                return
            }
            input.live = await readLiveState(asked: asked)
            guard !isQuitting else { return }
            // Taken again after the wait, as `BackgroundThrottleManager` takes it after its
            // reads: a licence lost while the helper answered must not be answered with an
            // engage. It has queued an evaluation of its own too. Only here: nothing else
            // waits between the gate and the decision, so a decision made without a reading
            // is made with the licence the gate saw.
            input.license = license
        }

        let reconciling = session.needsReconcile && input.live != nil
        // Without a record there is nothing a reconcile could find, so it is settled either way.
        if input.record == nil || input.live != nil {
            session.reconciled(at: asked)
        }

        var held = input.record
        for decision in AutoLowPowerModeEvaluation.decisions(input, reconcile: reconciling) {
            let step = AutoLowPowerModeEvaluation.step(for: decision, heldRecord: held, afterReconcile: reconciling)
            held = await carryOut(step, decision: decision, context: context)
        }
        updateTick()
    }

    /// The live setting, or nil — and after a slow nil, no more asking until a helper next
    /// becomes healthy. See `AutoLowPowerModeHelperSession`.
    private func readLiveState(asked: AutoLowPowerModeHelperSession.Mark) async -> PowerModeBySource? {
        var answer: PowerModeBySource?
        // Timed, because how long an "unknown" took is what tells an older helper that
        // lacks the call from one that simply could not read `pmset` this once.
        let elapsed = await clock.measure {
            answer = await powerModeClient.powerModeBySource()
        }
        guard let live = answer, live.battery != nil else {
            session.helperAnsweredUnknown(at: asked, after: elapsed)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            if session.mayAsk {
                logger.notice("The helper could not report Low Power Mode for the battery (after \(seconds, format: .fixed(precision: 1), privacy: .public)s); asking again on the next change")
            } else {
                logger.notice("The helper could not report Low Power Mode for the battery (after \(seconds, format: .fixed(precision: 1), privacy: .public)s); not asking again until a helper next becomes healthy")
            }
            return nil
        }
        return live
    }

    /// Carries out one step, in the same order as the sleep-disable ownership in
    /// `ChargingManager`: the record is stored before the write that makes it true and
    /// forgotten only after the write that makes it false. A process that dies in between
    /// is remembered as holding something it may not have set, which the next launch
    /// reconciles, rather than forgetting something it did set, which would leave Low Power
    /// Mode on with nothing that knows to give it back.
    ///
    /// - Returns: the record held afterwards.
    private func carryOut(
        _ step: AutoLowPowerModeEvaluation.Step,
        decision: AutoLowPowerModePolicy.Decision,
        context: Context
    ) async -> AutoLowPowerModeRecord? {
        let held = defaults.value(.autoLowPowerModeRecord)
        let reason = decision.reason.rawValue
        switch step {
        case let .engage(record):
            guard !isQuitting else { return held }
            let key = PowerModeBySource.pmsetKey(usesPowermodeKey: record.usesPowermodeKey)
            defaults.setValue(.autoLowPowerModeRecord, value: record)
            storeLatch(decision.yieldedUntilCharge)
            do {
                try await powerModeClient.setBatteryPowerMode(record.writtenBatteryValue, record.usesPowermodeKey)
            } catch {
                // Kept, not cleared: a write that failed may still have landed, with only the
                // reply lost, and clearing the record then would leave Low Power Mode on as
                // though the user had chosen it. The reconcile owed here settles it on the
                // next reading — the previous value clears the record without the hand-back
                // latch, the written one means BatFi holds it and arms the helper.
                session.writeMayHaveLanded()
                logger.error("Could not turn Low Power Mode on for the battery; keeping the record until the next reading settles it: \(error, privacy: .public)")
                return record
            }
            logger.notice("Turned Low Power Mode on for the battery at \(context.batteryLevel, privacy: .public)% (threshold \(context.threshold, privacy: .public)%); battery \(key, privacy: .public) was \(record.previousBatteryValue, privacy: .public) (\(reason, privacy: .public))")
            // A quit that began during the write owns the record now, so the user is not
            // told. The helper is armed all the same, so that it holds the record if the quit
            // stops waiting: a quit that gives up disarms nothing, and one that waits for this
            // evaluation reads, gives back and disarms only after this arm is answered. Not a
            // helper whose read stalled, which the quit asks nothing either.
            guard !isQuitting else {
                if session.mayAsk { await armHelper(with: record) }
                return record
            }
            await armHelper(with: record)
            // A quit that began while the helper was armed is about to give it back: not
            // news, and not counted as told, so the next launch still says it.
            guard !isQuitting else { return record }
            guard updateAnnouncement(engaged: true, context: context) else {
                logger.notice("Not announcing Low Power Mode again: the user was told during this discharge")
                return record
            }
            // Not awaited: asking for permission the first time waits for the user to
            // answer, and nothing else may queue behind that.
            Task { await announceEngaged() }
            return record

        case let .restore(value, record):
            let key = PowerModeBySource.pmsetKey(usesPowermodeKey: record.usesPowermodeKey)
            storeLatch(decision.yieldedUntilCharge)
            do {
                try await powerModeClient.setBatteryPowerMode(value, record.usesPowermodeKey)
            } catch {
                logger.error("Could not give Low Power Mode back; keeping the record to try again: \(error, privacy: .public)")
                return held
            }
            defaults.setValue(.autoLowPowerModeRecord, value: nil)
            logger.notice("Gave Low Power Mode back: battery \(key, privacy: .public) is \(value, privacy: .public) again (\(reason, privacy: .public))")
            await armHelper(with: nil)
            return nil

        case .forget:
            defaults.setValue(.autoLowPowerModeRecord, value: nil)
            storeLatch(decision.yieldedUntilCharge)
            if decision.reason == .handedBackToUser {
                logger.notice("Low Power Mode was changed since BatFi turned it on; leaving it to the user (\(reason, privacy: .public))")
            } else {
                logger.notice("Low Power Mode is already what BatFi found: the helper gave it back, or BatFi's write never landed; forgetting the record (\(reason, privacy: .public))")
            }
            await armHelper(with: nil)
            return nil

        case let .rearm(record):
            storeLatch(decision.yieldedUntilCharge)
            logger.notice("Still holding Low Power Mode on the battery; arming the helper to give it back (\(reason, privacy: .public))")
            await armHelper(with: record)
            return record

        case .none:
            storeLatch(decision.yieldedUntilCharge)
            logger.debug("Automatic Low Power Mode: nothing to change (\(reason, privacy: .public))")
            return held
        }
    }

    /// Stores the hand-back latch, and says so when it changes.
    private func storeLatch(_ yieldedUntilCharge: Bool) {
        guard defaults.value(.autoLowPowerModeYieldedUntilCharge) != yieldedUntilCharge else { return }
        defaults.setValue(.autoLowPowerModeYieldedUntilCharge, value: yieldedUntilCharge)
        if yieldedUntilCharge {
            logger.notice("Staying out of Low Power Mode until the Mac is next on the charger")
        } else {
            logger.notice("The Mac is on the charger; automatic Low Power Mode may turn on again")
        }
    }

    /// Remembers whether the user has been told during this discharge that Low Power Mode
    /// went on, and answers whether to tell them now. See
    /// `AutoLowPowerModeEvaluation.announcement`.
    @discardableResult
    private func updateAnnouncement(engaged: Bool, context: Context) -> Bool {
        let announced = defaults.value(.autoLowPowerModeAnnouncedThisDischarge)
        let next = AutoLowPowerModeEvaluation.announcement(
            onBattery: context.onBattery,
            batteryLevel: context.batteryLevel,
            threshold: context.threshold,
            engaged: engaged,
            announcedThisDischarge: announced
        )
        if next.announcedThisDischarge != announced {
            defaults.setValue(.autoLowPowerModeAnnouncedThisDischarge, value: next.announcedThisDischarge)
            if announced, context.onBattery {
                logger.notice("The battery is at \(context.batteryLevel, privacy: .public)% with the threshold at \(context.threshold, privacy: .public)%, where BatFi gives Low Power Mode back; the next time it turns on is announced")
            }
        }
        return next.post
    }

    /// Arms the helper to restore `record` as it exits, or disarms it with `nil`. A failure
    /// is logged and nothing more: the record is what the app acts on, and the helper's copy
    /// is only the fallback for a BatFi that is gone.
    private func armHelper(with record: AutoLowPowerModeRecord?) async {
        do {
            try await powerModeClient.armPowerModeRestoreOnExit(record)
        } catch {
            let action = record == nil ? "disarm" : "arm"
            logger.warning("Could not \(action, privacy: .public) the helper's Low Power Mode restore: \(error, privacy: .public)")
        }
    }

    private func announceEngaged() async {
        guard await userNotificationsClient.requestAuthorization() == true else { return }
        do {
            try await userNotificationsClient.showUserNotification(
                title: L10n.EnergySaving.lowPowerModeTurnedOnTitle,
                body: L10n.EnergySaving.lowPowerModeTurnedOnBody,
                identifier: "software.micropixels.BatFi.notifications.autoLowPowerMode",
                threadIdentifier: "powermode",
                delay: nil
            )
        } catch {
            logger.error("Could not post the Low Power Mode notification: \(error, privacy: .public)")
        }
    }
}
