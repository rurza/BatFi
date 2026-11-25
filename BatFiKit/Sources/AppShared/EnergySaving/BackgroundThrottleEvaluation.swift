//
//  BackgroundThrottleEvaluation.swift
//  BatFi
//
//  The glue between `BackgroundThrottlePolicy` and the manager that carries its plans out:
//  when a pass has anything to read, what it makes of audio it cannot read, which of its
//  loops run, how the ledger follows the kernel's answers, and what a pass reports. Pure,
//  like the policy, so the manager is left with calls and ordering and nothing to decide.
//

import Foundation

public enum BackgroundThrottleEvaluation {
    // MARK: - Whether anything may be slowed

    /// Whether a pass may slow anything down — the `isActive` every other question here is
    /// asked with: the master switch is on, the app licence is valid, and the Mac has been on
    /// its battery for `OnBatterySettle.duration`.
    ///
    /// Anything else takes the path the master switch going off takes: everything held is
    /// given back, what inherited a slowdown included, and nothing is slowed. A licence lost
    /// while running does exactly that, and so does one not read yet at launch — which gives
    /// back nothing a licence could have kept: whatever an earlier run left slowed is given
    /// back as the manager starts, whatever the licence (see
    /// `BackgroundThrottlePolicy.reconcileAtLaunch`), and this run slows nothing before the
    /// licence reads valid.
    ///
    /// - Parameter licenseAllowsTakingOn: `LicenseStatus.allowsTakingOn` — false without a
    ///   valid licence, and while the licence is not read yet.
    public static func isActive(
        isEnabled: Bool,
        licenseAllowsTakingOn: Bool,
        onBattery: Bool,
        batteryIsSettled: Bool
    ) -> Bool {
        isEnabled && licenseAllowsTakingOn && onBattery && batteryIsSettled
    }

    // MARK: - Whether a pass has anything to read

    /// Whether a pass can have anything to do, before anything is read.
    ///
    /// Nothing held and nothing that could be slowed is the state of every user who never
    /// slows an app: no pass then reads the running apps, the process table or audio.
    public static func mayHaveWork(
        isActive: Bool,
        slowedApps: [String: SlowDownMode],
        ledger: [ThrottleLedgerEntry]
    ) -> Bool {
        !ledger.isEmpty || (isActive && !slowedApps.isEmpty)
    }

    /// Whether an app the user slows is running — an eligible instance of it, which is all
    /// the policy ever slows.
    public static func isSlowedAppRunning(
        slowedApps: [String: SlowDownMode],
        runningApps: [RunningAppRecord]
    ) -> Bool {
        runningApps.contains { $0.isEligible && slowedApps[$0.bundleID] != nil }
    }

    /// Whether a pass needs the process table: to give back what the ledger holds, or to
    /// slow down an app that runs. Every give-back starts from a ledger entry, so with none
    /// held and nothing to slow there is nothing the table could show.
    public static func needsProcessTable(
        isActive: Bool,
        slowedAppIsRunning: Bool,
        ledger: [ThrottleLedgerEntry]
    ) -> Bool {
        !ledger.isEmpty || (isActive && slowedAppIsRunning)
    }

    /// Whether a pass reads audio. Audio only ever spares an app, so it is read only when
    /// something could be slowed; giving back never waits on it. Reading it otherwise would
    /// also start CoreAudio up inside BatFi for nothing.
    public static func needsAudio(isActive: Bool, slowedAppIsRunning: Bool) -> Bool {
        isActive && slowedAppIsRunning
    }

    /// Whether an app's grace after leaving the front running out is worth a pass. Only an
    /// app slowed in the background is spared for having just been in front, so for every
    /// other app the grace ending changes no plan — and every switch between apps would
    /// otherwise cost a second pass.
    public static func graceEndMatters(bundleID: String, slowedApps: [String: SlowDownMode]) -> Bool {
        slowedApps[bundleID] == .backgroundOnly
    }

    // MARK: - Audio

    /// The audio set to go on with after a reading, and whether it changed.
    ///
    /// A reading that failed (`nil`) is not silence: the last set known stays, since taking a
    /// playing process for a silent one would slow it and break its sound up. Before any
    /// reading has succeeded, audio stays unknown.
    public static func carryOver(
        known: Set<Int32>?,
        read: Set<Int32>?
    ) -> (known: Set<Int32>?, changed: Bool) {
        guard let read else { return (known, false) }
        return (read, read != known)
    }

    /// The policy's input, with audio that may not be known yet.
    ///
    /// With no audio set known, nothing is slowed — every coalition might be playing — but
    /// everything held is still given back, exactly as when the feature is inactive. Nothing
    /// was slowed before audio was first known, so what the ledger holds then is only what an
    /// earlier run left, and giving that back is always safe.
    public static func policyInput(
        isActive: Bool,
        slowedApps: [String: SlowDownMode],
        runningApps: [RunningAppRecord],
        processes: [ProcessRecord],
        frontmostPID: Int32?,
        frontmostBundleID: String?,
        recentlyActiveBundleIDs: Set<String>,
        knownAudioPIDs: Set<Int32>?,
        quittingBundleIDs: Set<String>,
        currentUID: UInt32,
        ownPID: Int32,
        ledger: [ThrottleLedgerEntry],
        unmanageable: Set<ProcessIdentity>
    ) -> BackgroundThrottlePolicy.Input {
        BackgroundThrottlePolicy.Input(
            isActive: isActive && knownAudioPIDs != nil,
            slowedApps: slowedApps,
            runningApps: runningApps,
            processes: processes,
            frontmostPID: frontmostPID,
            frontmostBundleID: frontmostBundleID,
            recentlyActiveBundleIDs: recentlyActiveBundleIDs,
            audioActivePIDs: knownAudioPIDs ?? [],
            quittingBundleIDs: quittingBundleIDs,
            currentUID: currentUID,
            ownPID: ownPID,
            ledger: ledger,
            unmanageable: unmanageable
        )
    }

    /// Whether a pass may slow anything, judged once its reads are done — the `isActive` to
    /// plan with.
    ///
    /// - Parameters:
    ///   - isActiveNow: the settings as they are after the reads. A charger connected, or the
    ///     switch turned off, while the pass was reading must not be answered with a slowdown.
    ///   - audioWasRead: whether this pass read audio, which it does only when it started
    ///     active with a slowed app running. One that started otherwise has only give-backs
    ///     to make; if something became slowable meanwhile, the change that made it so has
    ///     queued a pass that reads audio first.
    public static func maySlow(isActiveNow: Bool, audioWasRead: Bool) -> Bool {
        isActiveNow && audioWasRead
    }

    /// The give-back to make at quit when the process table cannot be read: every held
    /// process, by pid alone.
    ///
    /// Quitting is the last chance, so "always give back" wins over checking identities.
    /// Restoring a process that is not slowed is harmless, and a pid reused since belongs to
    /// a process whose original has exited anyway. Never launchd or the kernel, and never
    /// BatFi.
    ///
    /// What inherited a slowdown cannot be found without a table, so the ledger is left as it
    /// was: the next launch, with a table, gives those back through the entries' coalitions,
    /// gives the entries themselves back again — harmlessly — and forgets any whose pid
    /// another process has taken since.
    public static func blindGiveBack(ledger: [ThrottleLedgerEntry], ownPID: Int32) -> BackgroundThrottlePolicy.Plan {
        let held = ledger.map(\.identity).filter { $0.pid > 1 && $0.pid != ownPID }
        return BackgroundThrottlePolicy.Plan(restore: Set(held))
    }

    // MARK: - The process table

    /// Whether a snapshot can be planned from. One without BatFi's own process is a failed
    /// read — the client answers an empty table then — and the policy would plan nothing
    /// from it; the ledger stays for the next pass to try again.
    public static func isWhole(_ processes: [ProcessRecord], ownPID: Int32) -> Bool {
        processes.contains { $0.identity.pid == ownPID }
    }

    /// The refused processes still running, so that the set does not grow with every process
    /// that ever refused and exited.
    public static func stillRunning(
        _ unmanageable: Set<ProcessIdentity>,
        in processes: [ProcessRecord]
    ) -> Set<ProcessIdentity> {
        guard !unmanageable.isEmpty else { return [] }
        let alive = Set(processes.map(\.identity))
        return unmanageable.intersection(alive)
    }

    // MARK: - Loops

    /// What runs between passes. Each costs BatFi something, so each runs only while it can
    /// change what happens.
    public struct Loops: Equatable, Sendable {
        /// Looks again every ten seconds, for processes a slowed app starts that do not
        /// inherit the slowdown — launchd starts its XPC services — and for ledger entries
        /// whose process exited.
        public var rescan: Bool
        /// Follows CoreAudio's announcements, so that an app that starts or stops playing is
        /// spared or slowed.
        public var watchAudio: Bool
        /// Reads audio every two seconds: macOS does not reliably announce a process starting
        /// to play, and a slowed one that does breaks up until it is given back.
        public var pollAudio: Bool

        public init(rescan: Bool, watchAudio: Bool, pollAudio: Bool) {
            self.rescan = rescan
            self.watchAudio = watchAudio
            self.pollAudio = pollAudio
        }

        public static let none = Loops(rescan: false, watchAudio: false, pollAudio: false)
    }

    /// - Parameters:
    ///   - ledger: the ledger as the pass left it.
    ///   - owesRetry: the pass could not finish giving back: the process table could not be
    ///     read, or the kernel failed a give-back.
    public static func loops(
        isActive: Bool,
        slowedAppIsRunning: Bool,
        ledger: [ThrottleLedgerEntry],
        owesRetry: Bool
    ) -> Loops {
        let maySlow = isActive && slowedAppIsRunning
        return Loops(
            // Off battery nothing else would look again, and processes left slowed on the
            // charger are the one failure the feature must not leave standing.
            rescan: maySlow || (owesRetry && !ledger.isEmpty),
            watchAudio: maySlow,
            pollAudio: maySlow && !ledger.isEmpty
        )
    }

    // MARK: - The ledger

    /// Whether a give-back settles the ledger entry: the process is back, gone, or will
    /// never be allowed back — one that exec'd a setuid binary refuses from then on, and
    /// retrying it on every pass would change nothing.
    private static func settles(_ result: ThrottleResult) -> Bool {
        switch result {
        case .ok, .noSuchProcess, .notPermitted: true
        case .failed: false
        }
    }

    /// The ledger to write once the give-backs of a pass are done and before any of its
    /// demotions is made: forgotten and settled entries gone, re-recorded ones replaced where
    /// they stand, and every planned demotion added.
    ///
    /// Recording a demotion before making it means a crash in between leaves an entry for a
    /// process that may not be slowed — which the next launch gives back, harmlessly —
    /// rather than a slowed process nothing knows to give back.
    public static func ledger(
        _ ledger: [ThrottleLedgerEntry],
        carryingOut plan: BackgroundThrottlePolicy.Plan,
        restoreResults: [ProcessIdentity: ThrottleResult]
    ) -> [ThrottleLedgerEntry] {
        var gone = plan.forget
        for (identity, result) in restoreResults where settles(result) {
            gone.insert(identity)
        }
        var seen = Set<ProcessIdentity>()
        var next: [ThrottleLedgerEntry] = []
        for entry in ledger where !gone.contains(entry.identity) && seen.insert(entry.identity).inserted {
            next.append(plan.rerecord[entry.identity] ?? entry)
        }
        for identity in ordered(plan.demote.keys) where seen.insert(identity).inserted {
            if let entry = plan.demote[identity] { next.append(entry) }
        }
        return next
    }

    /// The ledger once the demotions are made: a planned demotion stays recorded only where
    /// the kernel accepted it. One that was not asked — BatFi began quitting first — was not
    /// made either.
    public static func ledger(
        _ ledger: [ThrottleLedgerEntry],
        afterDemoting planned: Set<ProcessIdentity>,
        results: [ProcessIdentity: ThrottleResult]
    ) -> [ThrottleLedgerEntry] {
        ledger.filter { !planned.contains($0.identity) || results[$0.identity] == .ok }
    }

    /// The processes the kernel refused, whichever way: left alone from then on.
    public static func refused(
        restoreResults: [ProcessIdentity: ThrottleResult],
        demoteResults: [ProcessIdentity: ThrottleResult]
    ) -> Set<ProcessIdentity> {
        let refusals = restoreResults.merging(demoteResults) { first, _ in first }
            .filter { $0.value == .notPermitted }
        return Set(refusals.keys)
    }

    /// Whether a held process could not be given back and is still in the ledger to try
    /// again. One that only inherited a slowdown was never in the ledger, so a pass would
    /// not find it again.
    public static func owesRetry(
        ledger: [ThrottleLedgerEntry],
        restoreResults: [ProcessIdentity: ThrottleResult]
    ) -> Bool {
        let held = Set(ledger.map(\.identity))
        return restoreResults.contains { held.contains($0.key) && !settles($0.value) }
    }

    // MARK: - The log

    /// What a pass did, as it is logged: per app, never per process.
    public struct PassReport: Equatable, Sendable {
        /// Processes slowed down, by the app they were slowed for.
        public var slowed: [String: Int]
        /// Held processes given back, by the app they were slowed for.
        public var givenBack: [String: Int]
        /// Processes given back that were never in the ledger: they inherited a slowdown.
        /// Kept apart, and out of the log's notices: inside a coalition shared with an app
        /// that is not slowed, these can come up on every pass.
        public var inheritedGivenBack: Int
        /// Processes the kernel refused, by the app they were slowed or held for.
        public var refused: [String: Int]
        /// Inherited processes the kernel refused to give back.
        public var inheritedRefused: Int
        /// Demotions and held give-backs that failed otherwise, by `errno`. Both are tried
        /// again: the policy plans the demotion again, and the entry stays in the ledger.
        public var failed: [Int32: Int]
        /// Inherited give-backs that failed otherwise, by `errno`. Not tried again: only a
        /// ledger entry leads a pass to an inherited process, and that entry has gone.
        public var inheritedFailed: [Int32: Int]

        public init(
            slowed: [String: Int] = [:],
            givenBack: [String: Int] = [:],
            inheritedGivenBack: Int = 0,
            refused: [String: Int] = [:],
            inheritedRefused: Int = 0,
            failed: [Int32: Int] = [:],
            inheritedFailed: [Int32: Int] = [:]
        ) {
            self.slowed = slowed
            self.givenBack = givenBack
            self.inheritedGivenBack = inheritedGivenBack
            self.refused = refused
            self.inheritedRefused = inheritedRefused
            self.failed = failed
            self.inheritedFailed = inheritedFailed
        }
    }

    /// - Parameter ledger: the ledger as the pass found it, which tells held processes from
    ///   inherited ones.
    public static func report(
        ledger: [ThrottleLedgerEntry],
        plan: BackgroundThrottlePolicy.Plan,
        restoreResults: [ProcessIdentity: ThrottleResult],
        demoteResults: [ProcessIdentity: ThrottleResult]
    ) -> PassReport {
        var heldFor: [ProcessIdentity: String] = [:]
        for entry in ledger where heldFor[entry.identity] == nil {
            heldFor[entry.identity] = entry.bundleID
        }

        var report = PassReport()
        for (identity, result) in restoreResults {
            let bundleID = heldFor[identity]
            switch (result, bundleID) {
            case let (.ok, bundleID?): report.givenBack[bundleID, default: 0] += 1
            case (.ok, nil): report.inheritedGivenBack += 1
            case let (.notPermitted, bundleID?): report.refused[bundleID, default: 0] += 1
            case (.notPermitted, nil): report.inheritedRefused += 1
            case (.failed(let code), _?): report.failed[code, default: 0] += 1
            case let (.failed(code), nil): report.inheritedFailed[code, default: 0] += 1
            case (.noSuchProcess, _): break
            }
        }
        for (identity, result) in demoteResults {
            let bundleID = plan.demote[identity]?.bundleID
            switch (result, bundleID) {
            case let (.ok, bundleID?): report.slowed[bundleID, default: 0] += 1
            case let (.notPermitted, bundleID?): report.refused[bundleID, default: 0] += 1
            case let (.failed(code), _): report.failed[code, default: 0] += 1
            case (.ok, nil), (.notPermitted, nil), (.noSuchProcess, _): break
            }
        }
        return report
    }

    // MARK: - Order

    /// The processes in pid order, then start time: the order a pass visits them in, so that
    /// the same plan makes the same calls and writes the same ledger every time.
    public static func ordered(_ identities: some Sequence<ProcessIdentity>) -> [ProcessIdentity] {
        identities.sorted { ($0.pid, $0.startSec, $0.startUsec) < ($1.pid, $1.startSec, $1.startUsec) }
    }
}
