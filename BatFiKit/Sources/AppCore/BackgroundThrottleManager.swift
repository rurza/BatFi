//
//  BackgroundThrottleManager.swift
//  BatFi
//
//  Keeps the apps the user slows down on battery on the efficiency cores while the Mac runs
//  on its battery, and always gives them back. Which processes to slow and which to give
//  back is `BackgroundThrottlePolicy`'s call, and when to look is
//  `BackgroundThrottleEvaluation`'s and `FrontmostGrace`'s. This actor makes the calls, in an
//  order that cannot lose track of a process it slowed.
//
//  Syscalls only: demoting a process of BatFi's own user needs no helper, so none of this
//  waits on XPC — at quit included.
//
//  It follows the app licence as charge management does: without a valid one it slows
//  nothing down and gives back everything it slowed.
//

import AppShared
import AsyncAlgorithms
import Clients
import DefaultsKeys
import Dependencies
import Foundation
import License
import os
import Shared

public actor BackgroundThrottleManager {
    private typealias Evaluation = BackgroundThrottleEvaluation

    private lazy var logger = Logger(category: "Background Throttle")
    @Dependency(\.appThrottleClient) private var client
    @Dependency(\.powerSourceClient) private var powerSourceClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.defaults) private var defaults
    @Dependency(\.suspendingClock) private var clock

    /// What a pass needs to know besides what it reads from the Mac.
    private struct Settings: Equatable, Sendable {
        let isEnabled: Bool
        let slowedApps: [String: SlowDownMode]
        let onBattery: Bool

        init(isEnabled: Bool, slowedApps: [String: SlowDownMode], powerState: PowerState, appMode: ChargingMode) {
            self.isEnabled = isEnabled
            self.slowedApps = slowedApps
            // The one answer every feature that acts "on battery" asks, so BatFi's own force
            // discharge counts as being on the charger.
            self.onBattery = ChargerConnection.isOnBattery(
                reported: powerState.chargerConnected,
                isDerived: powerState.chargerConnectionIsDerived,
                appMode: appMode
            )
        }
    }

    /// When a batch of give-backs happened, for the log.
    private enum Occasion {
        case pass
        case launch
        case quit
        case quitWithoutTable

        var givenBackNote: String {
            switch self {
            case .pass: ""
            case .launch: " (left slowed by an earlier run)"
            case .quit: " (quitting)"
            case .quitWithoutTable: " (quitting, by pid)"
            }
        }

        /// Whether the give-backs settle the ledger. A give-back by pid, at quit without a
        /// table, does not: it cannot reach what inherited the slowdown, and the entries it
        /// leaves let the next launch find those. See `BackgroundThrottleEvaluation.blindGiveBack`.
        var settlesLedger: Bool { self != .quitWithoutTable }

        /// Who tries a failed call again.
        var retryNote: String {
            switch self {
            case .pass, .launch: "trying again on the next pass"
            case .quit, .quitWithoutTable: "the next launch tries again"
            }
        }
    }

    private let ownPID = getpid()
    private let currentUID = getuid()

    /// Whether `setUpObserving()` has already run.
    private var isObserving = false
    /// Set by `appWillQuit()`: from then on no pass starts, and none still running slows
    /// anything more.
    private var isQuitting = false
    /// The latest settings, as the observation last delivered them. Nil until it has
    /// delivered once; no pass runs before that.
    private var settings: Settings?
    private var unlockModel: UnlockModel?
    /// The licence, or a running trial, as the unlock model last reported it. Unknown until
    /// both have been read: see `LicenseStatus`.
    private var license: LicenseStatus = .unknown
    /// Whether the Mac has been on its battery long enough to slow anything down.
    private var battery = OnBatterySettle()
    private var front = FrontmostGrace()
    /// The apps the high-energy list has just asked to quit, left alone meanwhile.
    private var quits = QuitExemptions()
    /// The processes last known to play or record audio; nil until audio was first read.
    private var knownAudio: Set<Int32>?
    /// Processes the kernel refused, left alone from then on.
    private var unmanageable: Set<ProcessIdentity> = []
    /// The pass running now, so that quitting can let it finish first.
    private var inFlight: Task<Void, Never>?
    private var rescan: Task<Void, Never>?
    private var audioWatch: Task<Void, Never>?
    private var audioPoll: Task<Void, Never>?

    /// Every trigger ends up here, and one consumer drains it, so passes never overlap.
    ///
    /// They must not: a pass awaits the kernel between recording a demotion and making it,
    /// and the actor is reentrant. A second pass interleaved into the first would plan from
    /// a ledger the first is about to change, and could give back what the first just slowed
    /// or record twice what it slowed once.
    ///
    /// A trigger carries nothing, since each pass starts from the Mac as it is then, so the
    /// buffer keeps only the newest: however many arrive during one pass, one more follows.
    private let triggers: AsyncStream<Void>
    private let trigger: AsyncStream<Void>.Continuation

    public init() {
        (triggers, trigger) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Before `setUpObserving()`, as for `ChargingManager`.
    public func setUnlockModel(_ unlockModel: UnlockModel) {
        self.unlockModel = unlockModel
    }

    public func setUpObserving() async {
        // Once only, for the reason `MagSafeColorManager.setUpObserving()` gives: the tasks
        // below are never retained, and `setUpTheApp()` is reached from two places.
        guard !isObserving else { return }
        isObserving = true

        // Before anything can slow an app down: a run that crashed may have left processes
        // slowed, and only its ledger knows which. Whatever the licence says, which is not
        // read yet.
        await giveBackWhatAnEarlierRunLeft()

        Task {
            for await _ in triggers {
                let pass = Task { await self.evaluate() }
                inFlight = pass
                await pass.value
                inFlight = nil
            }
        }

        // The master switch, the apps to slow, and whether the Mac is on its battery.
        // Deduplicated, so that the power source's frequent updates of things this does not
        // read — time remaining, temperature — cost no pass. Not debounced: giving back on
        // the charger, or when an app is taken off the list, should not wait.
        Task {
            for await settings in combineLatest(
                combineLatest(
                    defaults.observe(.slowDownAppsOnBattery),
                    defaults.observe(.slowedOnBatteryApps)
                ),
                combineLatest(
                    powerSourceClient.powerSourceChanges(),
                    appChargingState.appChargingModeDidChage()
                )
            )
            .map({ @Sendable element in
                Settings(
                    isEnabled: element.0.0,
                    slowedApps: element.0.1,
                    powerState: element.1.0,
                    appMode: element.1.1.mode
                )
            })
            .removeDuplicates()
            {
                settingsDidChange(settings)
            }
        }

        // The licence, read at once rather than on the next change or rescan: losing it gives
        // everything back, and activating one slows the apps down again with no relaunch. The
        // model's stream starts with the state it is in.
        if let unlockModel {
            Task {
                for await status in await unlockModel.statusChanges() {
                    licenseDidChange(status)
                }
            }
        } else {
            logger.error("No unlock model; no app is slowed down on battery")
            assertionFailure("setUnlockModel(_:) must be called before setUpObserving()")
        }

        let frontmost = client.frontmostChanges()
        Task {
            for await app in frontmost {
                frontmostDidChange(pid: app.pid, bundleID: app.bundleID)
            }
        }

        // An app launched or quit: a slowed app to slow, or one whose processes to forget.
        let launches = client.runningAppsChanges()
        let trigger = self.trigger
        Task {
            for await _ in launches {
                trigger.yield()
            }
        }

        // An app the high-energy list is about to ask to quit.
        let quitAnnouncements = client.quitAnnouncements()
        Task {
            for await bundleID in quitAnnouncements {
                appWillBeAskedToQuit(bundleID)
            }
        }
    }

    /// Gives back everything BatFi still holds slowed — every ledger entry and whatever
    /// inherited its slowdown — so that no app stays on the efficiency cores with no BatFi
    /// running to give it back on the charger. Without a process table, the held processes
    /// are still given back, by pid, and the ledger is kept for the next launch to give back
    /// what inherited their slowdown.
    ///
    /// Reads nothing and calls nothing when the ledger is empty.
    public func appWillQuit() async {
        isQuitting = true
        runLoops(.none)
        if let inFlight {
            // Bounded, though a pass waits on nothing slower than the process table. Once
            // `isQuitting` is set it slows nothing more.
            let finished = await waitAtMost(.seconds(2)) { await inFlight.value }
            if !finished {
                logger.warning("A pass was still running at quit; giving back what the ledger holds regardless")
            }
        }
        let ledger = defaults.value(.backgroundThrottleLedger)
        guard !ledger.isEmpty else { return }
        let processes = await client.processSnapshot()
        guard Evaluation.isWhole(processes, ownPID: ownPID) else {
            // The last chance: give back by pid alone rather than leave them slowed, and keep
            // the ledger for the next launch to give back what inherited the slowdown.
            logger.notice("Could not read the process table at quit; giving back \(Self.processes(ledger.count), privacy: .public) by pid and keeping them in the ledger, so the next launch also gives back what inherited their slowdown")
            await carryOut(
                Evaluation.blindGiveBack(ledger: ledger, ownPID: ownPID),
                ledger: ledger,
                occasion: .quitWithoutTable
            )
            return
        }
        let release = BackgroundThrottlePolicy.reconcileAtLaunch(
            ledger: ledger,
            processes: processes,
            currentUID: currentUID,
            ownPID: ownPID
        )
        let owed = await carryOut(
            BackgroundThrottlePolicy.Plan(restore: release.restore, forget: release.forget),
            ledger: ledger,
            occasion: .quit
        )
        if owed {
            logger.notice("Some slowed processes could not be given back at quit; the next launch tries again")
        }
    }

    // MARK: - Triggers

    /// Every change is acted on at once, except that going onto the battery slows nothing
    /// until the Mac has stayed there for `OnBatterySettle.duration` — see there. The wait's
    /// timer then asks for the pass that does.
    private func settingsDidChange(_ settings: Settings) {
        self.settings = settings
        if let wait = battery.powerChanged(onBattery: settings.onBattery) {
            let clock = self.clock
            Task {
                guard await OnBatterySettle.runOut(on: clock) else { return }
                batteryWaitRanOut(wait)
            }
        }
        trigger.yield()
    }

    private func batteryWaitRanOut(_ wait: OnBatterySettle.Wait) {
        guard battery.waitRanOut(wait), !isQuitting else { return }
        trigger.yield()
    }

    /// Asks for a pass at once, and says so once per change.
    private func licenseDidChange(_ next: LicenseStatus) {
        guard next != license else { return }
        license = next
        switch next {
        case .valid:
            logger.notice("Licence active — apps set to slow down on battery may be slowed down")
        case .invalid:
            logger.notice("Licence not active — no app is slowed down on battery, and any BatFi slowed are given back")
        case .unknown:
            break
        }
        guard !isQuitting else { return }
        trigger.yield()
    }

    /// Whether a pass may slow anything: see `BackgroundThrottleEvaluation.isActive`. Read
    /// together with `settings`, which the settle wait moves in step with; the licence is
    /// taken as it stands at the time.
    private func isActive(_ settings: Settings) -> Bool {
        Evaluation.isActive(
            isEnabled: settings.isEnabled,
            licenseAllowsTakingOn: license.allowsTakingOn,
            onBattery: settings.onBattery,
            batteryIsSettled: battery.isSettled
        )
    }

    /// An app coming to the front is looked at once, from a fresh snapshot, so that a slowed
    /// app the user turns to is given back at once. An app leaving it is looked at again only
    /// once its grace runs out.
    private func frontmostDidChange(pid: Int32?, bundleID: String?) {
        let change = front.frontmostChanged(pid: pid, bundleID: bundleID)
        if let grace = change.graceStarted {
            let clock = self.clock
            Task {
                guard await FrontmostGrace.runOut(on: clock) else { return }
                graceDidEnd(grace)
            }
        }
        if change.evaluateNow {
            trigger.yield()
        }
    }

    /// Gives the app back at once, and leaves it alone for `QuitExemptions.duration`; see
    /// there. Looked at whether or not the app is slowed itself: one started from a slowed
    /// app's process tree can be slowed with it.
    private func appWillBeAskedToQuit(_ bundleID: String) {
        guard !isQuitting else { return }
        let exemption = quits.exempt(bundleID)
        logger.notice("Leaving \(bundleID, privacy: .public) unslowed for \(QuitExemptions.duration.components.seconds, privacy: .public)s while it is asked to quit")
        let clock = self.clock
        Task {
            guard await QuitExemptions.runOut(on: clock) else { return }
            quitExemptionDidEnd(exemption)
        }
        trigger.yield()
    }

    /// The usual rules are back for the app: slowed again if it still runs and should be.
    private func quitExemptionDidEnd(_ exemption: QuitExemptions.Exemption) {
        guard quits.ended(exemption), !isQuitting else { return }
        trigger.yield()
    }

    private func graceDidEnd(_ grace: FrontmostGrace.Grace) {
        guard front.graceEnded(grace), !isQuitting, let settings else { return }
        guard Evaluation.graceEndMatters(bundleID: grace.bundleID, slowedApps: settings.slowedApps) else { return }
        trigger.yield()
    }

    /// Reads audio again, and asks for a pass only where the set changed. macOS announces
    /// every process that joins or leaves the audio system, not only those that start or
    /// stop playing.
    private func recheckAudio() async {
        guard !isQuitting else { return }
        let read = await client.audioActivePIDs()
        let next = Evaluation.carryOver(known: knownAudio, read: read)
        knownAudio = next.known
        if next.changed, !isQuitting {
            trigger.yield()
        }
    }

    // MARK: - Loops

    /// Starts and stops what runs between passes, so that each runs only while it can change
    /// what happens. See `BackgroundThrottleEvaluation.Loops`.
    private func runLoops(_ loops: Evaluation.Loops) {
        let loops = isQuitting ? .none : loops
        let trigger = self.trigger
        let clock = self.clock

        rescan = keep(rescan, running: loops.rescan) {
            Task {
                while true {
                    do {
                        try await clock.sleep(for: .seconds(10), tolerance: .seconds(5))
                    } catch {
                        return
                    }
                    trigger.yield()
                }
            }
        }

        audioPoll = keep(audioPoll, running: loops.pollAudio) {
            Task {
                while true {
                    do {
                        try await clock.sleep(for: .seconds(2), tolerance: .milliseconds(500))
                    } catch {
                        return
                    }
                    await recheckAudio()
                }
            }
        }

        audioWatch = keep(audioWatch, running: loops.watchAudio) {
            // They come in bursts: a process connecting announces itself more than once.
            // Not `debounce`: cancelled while a recheck runs, it never ends the stream, and the
            // CoreAudio listeners behind it would stay for the rest of the session.
            let changes = client.audioActivityChanges()
            return Task {
                await SettledSignals.forEach(changes, settlingFor: .milliseconds(300), on: clock) {
                    await self.recheckAudio()
                }
            }
        }
    }

    private func keep(
        _ task: Task<Void, Never>?,
        running: Bool,
        start: () -> Task<Void, Never>
    ) -> Task<Void, Never>? {
        switch (task, running) {
        case (nil, true):
            return start()
        case let (task?, false):
            task.cancel()
            return nil
        default:
            return task
        }
    }

    // MARK: - Passes

    private func evaluate() async {
        guard !isQuitting, let started = settings else { return }
        let startedActive = isActive(started)

        // Nothing held and nothing to slow: the state of every user who never slows an app.
        // Nothing is read.
        guard Evaluation.mayHaveWork(
            isActive: startedActive,
            slowedApps: started.slowedApps,
            ledger: defaults.value(.backgroundThrottleLedger)
        ) else {
            runLoops(.none)
            publishReport(runningApps: nil, planned: nil)
            return
        }

        let runningApps = await client.runningApps()
        let startedWithSlowedAppRunning = Evaluation.isSlowedAppRunning(
            slowedApps: started.slowedApps,
            runningApps: runningApps
        )
        guard Evaluation.needsProcessTable(
            isActive: startedActive,
            slowedAppIsRunning: startedWithSlowedAppRunning,
            ledger: defaults.value(.backgroundThrottleLedger)
        ) else {
            runLoops(.none)
            publishReport(runningApps: runningApps, planned: nil)
            return
        }

        // Side by side, so that reading audio does not hold up giving back an app that just
        // came to the front.
        let readsAudio = Evaluation.needsAudio(isActive: startedActive, slowedAppIsRunning: startedWithSlowedAppRunning)
        let client = self.client
        async let audioReading: Set<Int32>? = readsAudio ? client.audioActivePIDs() : nil
        async let snapshot = client.processSnapshot()
        let (read, processes) = await (audioReading, snapshot)
        if readsAudio {
            knownAudio = Evaluation.carryOver(known: knownAudio, read: read).known
            if knownAudio == nil {
                logger.debug("Audio activity is not known yet; slowing nothing until it is")
            }
        }

        // Read after the awaits, like the ledger and the app in front: a charger connected,
        // the switch turned off, or the licence lost while the pass was reading must not be
        // answered with a slowdown. It has queued a pass of its own too.
        guard !isQuitting, let settings else { return }
        let isActiveNow = isActive(settings)
        let slowedAppIsRunning = Evaluation.isSlowedAppRunning(slowedApps: settings.slowedApps, runningApps: runningApps)
        // Only passes and the quit change the ledger, and neither ran since.
        let ledger = defaults.value(.backgroundThrottleLedger)
        guard Evaluation.isWhole(processes, ownPID: ownPID) else {
            // The client says so at notice; the ledger stays for the next pass.
            logger.debug("No whole process table; keeping \(ledger.count, privacy: .public) ledger entries for the next pass")
            runLoops(Evaluation.loops(isActive: isActiveNow, slowedAppIsRunning: slowedAppIsRunning, ledger: ledger, owesRetry: true))
            return
        }

        unmanageable = Evaluation.stillRunning(unmanageable, in: processes)
        let input = Evaluation.policyInput(
            isActive: Evaluation.maySlow(isActiveNow: isActiveNow, audioWasRead: readsAudio),
            slowedApps: settings.slowedApps,
            runningApps: runningApps,
            processes: processes,
            frontmostPID: front.frontmostPID,
            frontmostBundleID: front.frontmostBundleID,
            recentlyActiveBundleIDs: front.recentlyActiveBundleIDs,
            knownAudioPIDs: knownAudio,
            quittingBundleIDs: quits.bundleIDs,
            currentUID: currentUID,
            ownPID: ownPID,
            ledger: ledger,
            unmanageable: unmanageable
        )
        let plan = BackgroundThrottlePolicy.plan(input)
        let owesRetry = await carryOut(plan, ledger: ledger, occasion: .pass)
        runLoops(Evaluation.loops(
            isActive: isActiveNow,
            slowedAppIsRunning: slowedAppIsRunning,
            ledger: defaults.value(.backgroundThrottleLedger),
            owesRetry: owesRetry
        ))
        publishReport(runningApps: runningApps, planned: input)
    }

    /// Tells the menu, after a pass, whether the Mac is on its battery, whether the licence is
    /// active, and whether each app
    /// in the list is slowed right now and if not, why: see `SlowDownReport`. A pass that
    /// could not read the process table, or ended because BatFi is quitting, leaves what was
    /// said last.
    ///
    /// - Parameters:
    ///   - runningApps: the running apps, where the pass read them.
    ///   - planned: what the pass planned from, where it planned.
    private func publishReport(runningApps: [RunningAppRecord]?, planned: BackgroundThrottlePolicy.Input?) {
        guard !isQuitting, let settings else { return }
        let licence: SlowDownStatus.Licence = switch license {
        case .valid: .valid
        case .invalid: .invalid
        case .unknown: .unknown
        }
        let statuses = SlowDownStatus.statuses(SlowDownStatus.Input(
            slowedApps: settings.slowedApps,
            isEnabled: settings.isEnabled,
            licence: licence,
            onBattery: settings.onBattery,
            batteryIsSettled: battery.isSettled,
            runningApps: runningApps,
            planned: planned,
            refused: unmanageable,
            ledger: defaults.value(.backgroundThrottleLedger)
        ))
        client.publishSlowDownReport(SlowDownReport(onBattery: settings.onBattery, licence: licence, statuses: statuses))
    }

    /// What an earlier run left slowed, given back before this one slows anything. A table
    /// that could not be read keeps the ledger for the first pass, which gives back whatever
    /// it no longer wants slowed; so does a give-back the kernel failed.
    private func giveBackWhatAnEarlierRunLeft() async {
        let ledger = defaults.value(.backgroundThrottleLedger)
        guard !ledger.isEmpty else { return }
        let processes = await client.processSnapshot()
        guard Evaluation.isWhole(processes, ownPID: ownPID) else {
            logger.notice("Could not read the process table at launch; keeping \(ledger.count, privacy: .public) processes an earlier run left slowed for the next pass to give back")
            return
        }
        let release = BackgroundThrottlePolicy.reconcileAtLaunch(
            ledger: ledger,
            processes: processes,
            currentUID: currentUID,
            ownPID: ownPID
        )
        await carryOut(
            BackgroundThrottlePolicy.Plan(restore: release.restore, forget: release.forget),
            ledger: ledger,
            occasion: .launch
        )
    }

    /// Carries out a plan: give-backs first, then the ledger written once — with every
    /// planned demotion already in it — then the demotions, and the ledger written again only
    /// where the kernel refused one.
    ///
    /// Give-backs need nothing recorded first: a crash after one leaves a ledger entry for a
    /// process no longer slowed, which the next launch gives back again, harmlessly.
    /// Demotions are recorded before they are made, for the same reason the other way round:
    /// a slowed process the ledger does not hold would stay slowed for good.
    ///
    /// - Returns: whether a held process could not be given back and is owed a retry.
    @discardableResult
    private func carryOut(
        _ plan: BackgroundThrottlePolicy.Plan,
        ledger: [ThrottleLedgerEntry],
        occasion: Occasion
    ) async -> Bool {
        guard !plan.isEmpty else { return false }

        var restoreResults: [ProcessIdentity: ThrottleResult] = [:]
        for identity in Evaluation.ordered(plan.restore) {
            restoreResults[identity] = await client.setBackground(identity.pid, false)
        }

        var plan = plan
        // A quit that began during the give-backs owns the ledger now.
        if isQuitting { plan.demote = [:] }
        let recorded = occasion.settlesLedger
            ? Evaluation.ledger(ledger, carryingOut: plan, restoreResults: restoreResults)
            : ledger
        if recorded != ledger {
            defaults.setValue(.backgroundThrottleLedger, value: recorded)
        }

        var demoteResults: [ProcessIdentity: ThrottleResult] = [:]
        for identity in Evaluation.ordered(plan.demote.keys) {
            guard !isQuitting else { break }
            demoteResults[identity] = await client.setBackground(identity.pid, true)
        }
        let settled = Evaluation.ledger(recorded, afterDemoting: Set(plan.demote.keys), results: demoteResults)
        if settled != recorded {
            defaults.setValue(.backgroundThrottleLedger, value: settled)
        }

        unmanageable.formUnion(Evaluation.refused(restoreResults: restoreResults, demoteResults: demoteResults))
        log(
            Evaluation.report(ledger: ledger, plan: plan, restoreResults: restoreResults, demoteResults: demoteResults),
            occasion: occasion
        )
        return Evaluation.owesRetry(ledger: ledger, restoreResults: restoreResults)
    }

    /// One line per app and batch, never per process. Refusals are logged once: a refused
    /// process is left alone from then on.
    private func log(_ report: Evaluation.PassReport, occasion: Occasion) {
        for (bundleID, count) in report.slowed.sorted(by: { $0.key < $1.key }) {
            logger.notice("Slowed \(bundleID, privacy: .public) down on battery: \(Self.processes(count), privacy: .public) moved to the efficiency cores")
        }
        for (bundleID, count) in report.givenBack.sorted(by: { $0.key < $1.key }) {
            logger.notice("Gave \(bundleID, privacy: .public) back\(occasion.givenBackNote, privacy: .public): \(Self.processes(count), privacy: .public) off the efficiency cores")
        }
        if report.inheritedGivenBack > 0 {
            logger.debug("Also gave back \(Self.processes(report.inheritedGivenBack), privacy: .public) that inherited a slowdown\(occasion.givenBackNote, privacy: .public)")
        }
        for (bundleID, count) in report.refused.sorted(by: { $0.key < $1.key }) {
            logger.notice("macOS refused to slow down or give back \(Self.processes(count), privacy: .public) of \(bundleID, privacy: .public); leaving them alone from now on")
        }
        if report.inheritedRefused > 0 {
            logger.notice("macOS refused to give back \(Self.processes(report.inheritedRefused), privacy: .public) that inherited a slowdown; leaving them alone from now on")
        }
        for (code, count) in report.failed.sorted(by: { $0.key < $1.key }) {
            logger.notice("Could not slow down or give back \(Self.processes(count), privacy: .public): \(String(cString: strerror(code)), privacy: .public) (\(code, privacy: .public)); \(occasion.retryNote, privacy: .public)")
        }
        for (code, count) in report.inheritedFailed.sorted(by: { $0.key < $1.key }) {
            logger.notice("Could not give back \(Self.processes(count), privacy: .public) that inherited a slowdown: \(String(cString: strerror(code)), privacy: .public) (\(code, privacy: .public)); they stay slowed until they exit")
        }
    }

    private static func processes(_ count: Int) -> String {
        count == 1 ? "1 process" : "\(count) processes"
    }
}
