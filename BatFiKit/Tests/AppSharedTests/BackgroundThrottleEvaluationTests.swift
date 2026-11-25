//
//  BackgroundThrottleEvaluationTests.swift
//  BatFi
//
//  Unit tests for the glue between `BackgroundThrottlePolicy` and the manager that carries
//  its plans out: when a pass has anything to read, what it does with audio it cannot read,
//  which loops run, how the ledger follows the kernel's answers, and what gets logged.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct BackgroundThrottleEvaluationTests {
    private typealias Evaluation = BackgroundThrottleEvaluation
    private typealias Plan = BackgroundThrottlePolicy.Plan

    private let me: UInt32 = 501
    private let root: UInt32 = 0
    private let batFiPID: Int32 = 900

    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"

    private func id(_ pid: Int32, startedAt start: UInt64? = nil) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startSec: start ?? 1_700_000_000 + UInt64(pid), startUsec: 250)
    }

    private func process(_ pid: Int32, parent ppid: Int32 = 1, uid: UInt32? = nil, coalition: UInt64?) -> ProcessRecord {
        ProcessRecord(identity: id(pid), ppid: ppid, uid: uid ?? me, coalitionID: coalition)
    }

    private func entry(_ pid: Int32, _ bundleID: String, coalition: UInt64? = 10) -> ThrottleLedgerEntry {
        ThrottleLedgerEntry(identity: id(pid), bundleID: bundleID, coalitionID: coalition)
    }

    private func running(_ bundleID: String, _ pid: Int32, eligible: Bool = true) -> RunningAppRecord {
        RunningAppRecord(bundleID: bundleID, pid: pid, isEligible: eligible, isRegular: true)
    }

    /// launchd, BatFi, and Slack (coalition 10) with a helper.
    private var world: [ProcessRecord] {
        [
            process(1, parent: 0, uid: root, coalition: 1),
            process(batFiPID, coalition: 90),
            process(100, coalition: 10),
            process(101, parent: 100, coalition: 10),
        ]
    }

    // MARK: - Whether a pass has anything to read

    @Test func aPassWithNothingSlowedAndNothingHeldHasNoWork() {
        #expect(!Evaluation.mayHaveWork(isActive: true, slowedApps: [:], ledger: []))
        #expect(!Evaluation.mayHaveWork(isActive: false, slowedApps: [slack: .backgroundOnly], ledger: []))
    }

    @Test func aPassHasWorkWhileSomethingIsHeldOrAnAppCouldBeSlowed() {
        #expect(Evaluation.mayHaveWork(isActive: false, slowedApps: [:], ledger: [entry(100, slack)]))
        #expect(Evaluation.mayHaveWork(isActive: true, slowedApps: [slack: .always], ledger: []))
    }

    @Test func onlyAnEligibleRunningInstanceOfASlowedAppCounts() {
        let slowed: [String: SlowDownMode] = [slack: .backgroundOnly]
        #expect(Evaluation.isSlowedAppRunning(slowedApps: slowed, runningApps: [running(slack, 100)]))
        #expect(!Evaluation.isSlowedAppRunning(slowedApps: slowed, runningApps: [running(slack, 100, eligible: false)]))
        #expect(!Evaluation.isSlowedAppRunning(slowedApps: slowed, runningApps: [running(safari, 200)]))
        #expect(!Evaluation.isSlowedAppRunning(slowedApps: [:], runningApps: [running(slack, 100)]))
    }

    @Test func theProcessTableIsReadWhileSomethingIsHeldOrASlowedAppRuns() {
        #expect(Evaluation.needsProcessTable(isActive: false, slowedAppIsRunning: false, ledger: [entry(100, slack)]))
        #expect(Evaluation.needsProcessTable(isActive: true, slowedAppIsRunning: true, ledger: []))
        #expect(!Evaluation.needsProcessTable(isActive: true, slowedAppIsRunning: false, ledger: []))
        #expect(!Evaluation.needsProcessTable(isActive: false, slowedAppIsRunning: true, ledger: []))
    }

    /// Audio only decides what may be slowed; giving back never waits on it. Reading it for
    /// nothing would also start CoreAudio up in BatFi for users who slow nothing.
    @Test func audioIsReadOnlyWhenSomethingCouldBeSlowed() {
        #expect(Evaluation.needsAudio(isActive: true, slowedAppIsRunning: true))
        #expect(!Evaluation.needsAudio(isActive: true, slowedAppIsRunning: false))
        #expect(!Evaluation.needsAudio(isActive: false, slowedAppIsRunning: true))
    }

    /// Only an app slowed in the background is spared for having just left the front, so
    /// only its grace running out can change a plan.
    @Test func onlyTheGraceOfAnAppSlowedInTheBackgroundIsWorthAPass() {
        #expect(Evaluation.graceEndMatters(bundleID: slack, slowedApps: [slack: .backgroundOnly]))
        #expect(!Evaluation.graceEndMatters(bundleID: slack, slowedApps: [slack: .always]))
        #expect(!Evaluation.graceEndMatters(bundleID: slack, slowedApps: [safari: .backgroundOnly]))
    }

    // MARK: - Audio

    @Test func aFreshAudioReadingReplacesTheLastOne() {
        let next = Evaluation.carryOver(known: [100], read: [200])
        #expect(next.known == [200])
        #expect(next.changed)
    }

    @Test func anUnreadableAudioReadingKeepsTheLastKnownSet() {
        let next = Evaluation.carryOver(known: [100], read: nil)
        #expect(next.known == [100])
        #expect(!next.changed)
    }

    @Test func theSameAudioReadingIsNoChange() {
        let next = Evaluation.carryOver(known: [100], read: [100])
        #expect(next.known == [100])
        #expect(!next.changed)
    }

    @Test func audioStaysUnknownUntilItIsFirstRead() {
        let failed = Evaluation.carryOver(known: nil, read: nil)
        #expect(failed.known == nil)
        #expect(!failed.changed)

        let first = Evaluation.carryOver(known: nil, read: [])
        #expect(first.known == [])
        #expect(first.changed)
    }

    private func input(
        knownAudio: Set<Int32>?,
        quitting: Set<String> = [],
        ledger: [ThrottleLedgerEntry] = []
    ) -> BackgroundThrottlePolicy.Input {
        Evaluation.policyInput(
            isActive: true,
            slowedApps: [slack: .always],
            runningApps: [running(slack, 100)],
            processes: world,
            frontmostPID: nil,
            frontmostBundleID: nil,
            recentlyActiveBundleIDs: [],
            knownAudioPIDs: knownAudio,
            quittingBundleIDs: quitting,
            currentUID: me,
            ownPID: batFiPID,
            ledger: ledger,
            unmanageable: []
        )
    }

    @Test func withAudioNeverReadNothingIsSlowedButWhatIsHeldIsStillGivenBack() {
        let slowsNothing = BackgroundThrottlePolicy.plan(input(knownAudio: nil))
        #expect(slowsNothing.demote.isEmpty)

        let givesBack = BackgroundThrottlePolicy.plan(input(knownAudio: nil, ledger: [entry(100, slack)]))
        #expect(givesBack.demote.isEmpty)
        #expect(givesBack.restore == [id(100), id(101)])
    }

    @Test func aPassSlowsOnlyIfItReadAudioAndIsStillActiveOnceItsReadsAreDone() {
        #expect(Evaluation.maySlow(isActiveNow: true, audioWasRead: true))
        // The charger came in, or the switch went off, while the pass was reading.
        #expect(!Evaluation.maySlow(isActiveNow: false, audioWasRead: true))
        // It started with nothing to slow, so it read no audio; the pass the change queued
        // reads it and slows.
        #expect(!Evaluation.maySlow(isActiveNow: true, audioWasRead: false))
    }

    @Test func goingOnTheChargerDuringAPassGivesBackInsteadOfSlowing() {
        let input = Evaluation.policyInput(
            isActive: Evaluation.maySlow(isActiveNow: false, audioWasRead: true),
            slowedApps: [slack: .always],
            runningApps: [running(slack, 100)],
            processes: world,
            frontmostPID: nil,
            frontmostBundleID: nil,
            recentlyActiveBundleIDs: [],
            knownAudioPIDs: [],
            quittingBundleIDs: [],
            currentUID: me,
            ownPID: batFiPID,
            ledger: [entry(100, slack)],
            unmanageable: []
        )
        let plan = BackgroundThrottlePolicy.plan(input)
        #expect(plan.demote.isEmpty)
        #expect(plan.restore == [id(100), id(101)])
    }

    @Test func aKnownAudioSetReachesThePolicy() {
        let silent = BackgroundThrottlePolicy.plan(input(knownAudio: []))
        #expect(Set(silent.demote.keys) == [id(100), id(101)])

        let playing = BackgroundThrottlePolicy.plan(input(knownAudio: [101]))
        #expect(playing.demote.isEmpty)
    }

    @Test func theAppsAskedToQuitReachThePolicy() {
        let asked = BackgroundThrottlePolicy.plan(input(knownAudio: [], quitting: [slack], ledger: [entry(100, slack)]))
        #expect(asked.demote.isEmpty)
        #expect(asked.restore == [id(100), id(101)])
    }

    // MARK: - Whether anything may be slowed

    @Test func appsAreSlowedOnlyWithTheSwitchOnALicenceAndASettledBattery() {
        #expect(Evaluation.isActive(isEnabled: true, licenseAllowsTakingOn: true, onBattery: true, batteryIsSettled: true))
        #expect(!Evaluation.isActive(isEnabled: false, licenseAllowsTakingOn: true, onBattery: true, batteryIsSettled: true))
        #expect(!Evaluation.isActive(isEnabled: true, licenseAllowsTakingOn: true, onBattery: false, batteryIsSettled: true))
        #expect(!Evaluation.isActive(isEnabled: true, licenseAllowsTakingOn: true, onBattery: true, batteryIsSettled: false))
    }

    /// Without a valid licence — or before it has been read at launch — the feature is off,
    /// whatever the switch says.
    @Test func nothingIsSlowedWithoutAValidLicence() {
        let isActive = Evaluation.isActive(isEnabled: true, licenseAllowsTakingOn: false, onBattery: true, batteryIsSettled: true)
        #expect(!isActive)

        let plan = BackgroundThrottlePolicy.plan(slackPass(isActive: isActive, ledger: []))
        #expect(plan.isEmpty)
    }

    /// Losing the licence is the master switch going off: everything held is given back,
    /// what inherited the slowdown included, and nothing is slowed.
    @Test func losingTheLicenceGivesBackEverythingHeld() {
        let isActive = Evaluation.isActive(isEnabled: true, licenseAllowsTakingOn: false, onBattery: true, batteryIsSettled: true)
        let world = self.world + [process(102, coalition: 10)]

        let plan = BackgroundThrottlePolicy.plan(slackPass(isActive: isActive, processes: world, ledger: [entry(100, slack)]))

        #expect(plan.demote.isEmpty)
        // 102 was never recorded: it inherited the slowdown.
        #expect(plan.restore == [id(100), id(101), id(102)])
    }

    /// Activating a licence while running slows the apps down again, with no relaunch.
    @Test func gainingTheLicenceSlowsAgain() {
        let isActive = Evaluation.isActive(isEnabled: true, licenseAllowsTakingOn: true, onBattery: true, batteryIsSettled: true)

        let plan = BackgroundThrottlePolicy.plan(slackPass(isActive: isActive, ledger: []))

        #expect(Set(plan.demote.keys) == [id(100), id(101)])
    }

    /// Slack, running and slowed always, on a pass that read audio and found it silent.
    private func slackPass(
        isActive: Bool,
        processes: [ProcessRecord]? = nil,
        ledger: [ThrottleLedgerEntry]
    ) -> BackgroundThrottlePolicy.Input {
        Evaluation.policyInput(
            isActive: Evaluation.maySlow(isActiveNow: isActive, audioWasRead: true),
            slowedApps: [slack: .always],
            runningApps: [running(slack, 100)],
            processes: processes ?? world,
            frontmostPID: nil,
            frontmostBundleID: nil,
            recentlyActiveBundleIDs: [],
            knownAudioPIDs: [],
            quittingBundleIDs: [],
            currentUID: me,
            ownPID: batFiPID,
            ledger: ledger,
            unmanageable: []
        )
    }

    // MARK: - The process table

    @Test func aTableWithoutBatFiIsNotWhole() {
        #expect(!Evaluation.isWhole([], ownPID: batFiPID))
        #expect(!Evaluation.isWhole(world.filter { $0.identity.pid != batFiPID }, ownPID: batFiPID))
        #expect(Evaluation.isWhole(world, ownPID: batFiPID))
    }

    /// Quitting is the last chance to give back. Without a table, the held processes are
    /// given back by pid alone: restoring a process that is not slowed is harmless, and a
    /// reused pid belongs to a process whose original has exited anyway.
    @Test func withoutAProcessTableAtQuitEveryHeldProcessIsGivenBackByPID() {
        let held = [entry(100, slack), entry(101, slack), entry(1, slack), entry(batFiPID, slack), entry(0, slack)]
        let plan = Evaluation.blindGiveBack(ledger: held, ownPID: batFiPID)
        #expect(plan == Plan(restore: [id(100), id(101)]))
    }

    /// A give-back by pid cannot reach what inherited the slowdown, so the entries stay in
    /// the ledger after it: the next launch, with a table, gives those back through their
    /// coalitions, gives the entry itself back again — harmlessly — and forgets a pid that
    /// another process has taken since.
    @Test func entriesKeptAfterABlindGiveBackLetTheNextLaunchGiveBackWhatInheritedTheSlowdown() {
        let held = [entry(100, slack), entry(102, slack, coalition: 20)]
        let nextLaunch = [
            process(1, parent: 0, uid: root, coalition: 1),
            process(batFiPID, coalition: 90),
            // Slack's helper, which inherited the slowdown; the app itself was given back by pid.
            process(100, coalition: 10),
            process(101, parent: 100, coalition: 10),
            // 102 exited and its pid went to an unrelated process.
            ProcessRecord(identity: ProcessIdentity(pid: 102, startSec: 1_800_000_000, startUsec: 0), ppid: 1, uid: me, coalitionID: 40),
            // What 102 spawned lives on in its coalition.
            process(103, coalition: 20),
        ]
        let reconciled = BackgroundThrottlePolicy.reconcileAtLaunch(
            ledger: held,
            processes: nextLaunch,
            currentUID: me,
            ownPID: batFiPID
        )
        #expect(reconciled.restore == [id(100), id(101), id(103)])
        #expect(reconciled.forget == [id(102)])
    }

    @Test func refusedProcessesAreForgottenOnceTheyExit() {
        let reused = ProcessIdentity(pid: 101, startSec: 1, startUsec: 0)
        let kept = Evaluation.stillRunning([id(100), reused, id(555)], in: world)
        #expect(kept == [id(100)])
    }

    // MARK: - Loops

    @Test func whileAnAppCanBeSlowedTheRescanAndAudioWatchRunButThePollWaitsForADemotion() {
        let loops = Evaluation.loops(isActive: true, slowedAppIsRunning: true, ledger: [], owesRetry: false)
        #expect(loops == Evaluation.Loops(rescan: true, watchAudio: true, pollAudio: false))
    }

    @Test func whileAnAppIsSlowedAudioIsPolled() {
        let loops = Evaluation.loops(isActive: true, slowedAppIsRunning: true, ledger: [entry(100, slack)], owesRetry: false)
        #expect(loops == Evaluation.Loops(rescan: true, watchAudio: true, pollAudio: true))
    }

    @Test func nothingRunsWithNoSlowedAppRunningOrOffBattery() {
        #expect(Evaluation.loops(isActive: true, slowedAppIsRunning: false, ledger: [], owesRetry: false) == .none)
        #expect(Evaluation.loops(isActive: false, slowedAppIsRunning: true, ledger: [], owesRetry: false) == .none)
        #expect(Evaluation.loops(isActive: false, slowedAppIsRunning: true, ledger: [entry(100, slack)], owesRetry: false) == .none)
    }

    /// Off battery nothing else would look again, and processes left slowed on the charger
    /// are the one failure the feature must not leave standing.
    @Test func aGiveBackStillOwedKeepsTheRescanRunningOffBattery() {
        let loops = Evaluation.loops(isActive: false, slowedAppIsRunning: false, ledger: [entry(100, slack)], owesRetry: true)
        #expect(loops == Evaluation.Loops(rescan: true, watchAudio: false, pollAudio: false))
        #expect(Evaluation.loops(isActive: false, slowedAppIsRunning: false, ledger: [], owesRetry: true) == .none)
    }

    // MARK: - The ledger

    @Test func newDemotionsAreRecordedBeforeTheyAreMade() {
        let plan = Plan(demote: [id(102): entry(102, slack), id(101): entry(101, slack)])
        let ledger = Evaluation.ledger([entry(100, slack)], carryingOut: plan, restoreResults: [:])
        #expect(ledger == [entry(100, slack), entry(101, slack), entry(102, slack)])
    }

    @Test func givenBackExitedAndRefusedEntriesGoWhileFailedOnesStay() {
        let held = [entry(100, slack), entry(101, slack), entry(102, slack), entry(103, slack), entry(104, slack)]
        let plan = Plan(restore: [id(100), id(101), id(102), id(103), id(200)], forget: [id(104)])
        let results: [ProcessIdentity: ThrottleResult] = [
            id(100): .ok,
            id(101): .noSuchProcess,
            id(102): .notPermitted,
            id(103): .failed(EINVAL),
            id(200): .ok,
        ]
        let ledger = Evaluation.ledger(held, carryingOut: plan, restoreResults: results)
        #expect(ledger == [entry(103, slack)])
    }

    @Test func rerecordedEntriesAreReplacedInPlace() {
        let held = [entry(100, slack, coalition: nil), entry(101, slack)]
        let plan = Plan(rerecord: [id(100): entry(100, slack, coalition: 10)])
        let ledger = Evaluation.ledger(held, carryingOut: plan, restoreResults: [:])
        #expect(ledger == [entry(100, slack, coalition: 10), entry(101, slack)])
    }

    @Test func aPassWithNothingToChangeLeavesTheLedgerAsItWas() {
        let held = [entry(101, slack), entry(100, slack)]
        #expect(Evaluation.ledger(held, carryingOut: Plan(), restoreResults: [:]) == held)
    }

    @Test func aDuplicatedEntryIsKeptOnce() {
        let held = [entry(100, slack), entry(100, safari)]
        #expect(Evaluation.ledger(held, carryingOut: Plan(), restoreResults: [:]) == [entry(100, slack)])
    }

    @Test func onlyDemotionsTheKernelAcceptedStayRecorded() {
        let held = [entry(100, slack), entry(101, slack), entry(102, slack), entry(103, slack), entry(104, slack), entry(105, slack)]
        let planned: Set<ProcessIdentity> = [id(101), id(102), id(103), id(104), id(105)]
        let results: [ProcessIdentity: ThrottleResult] = [
            id(101): .ok,
            id(102): .noSuchProcess,
            id(103): .notPermitted,
            id(104): .failed(EINVAL),
            // 105 was never asked: BatFi began quitting first.
        ]
        let ledger = Evaluation.ledger(held, afterDemoting: planned, results: results)
        #expect(ledger == [entry(100, slack), entry(101, slack)])
    }

    @Test func refusedProcessesFromEitherDirectionAreLeftAloneFromThenOn() {
        let refused = Evaluation.refused(
            restoreResults: [id(100): .notPermitted, id(101): .ok],
            demoteResults: [id(200): .notPermitted, id(201): .failed(EINVAL)]
        )
        #expect(refused == [id(100), id(200)])
    }

    @Test func aFailedGiveBackOfAHeldProcessIsOwedARetry() {
        let held = [entry(100, slack)]
        #expect(Evaluation.owesRetry(ledger: held, restoreResults: [id(100): .failed(EINVAL)]))
        #expect(!Evaluation.owesRetry(ledger: held, restoreResults: [id(100): .ok]))
        #expect(!Evaluation.owesRetry(ledger: held, restoreResults: [id(100): .notPermitted]))
        // One that only inherited a slowdown is no longer reachable through the ledger.
        #expect(!Evaluation.owesRetry(ledger: held, restoreResults: [id(300): .failed(EINVAL)]))
    }

    // MARK: - The log

    @Test func theReportCountsEachBatchByAppAndKeepsInheritedGiveBacksApart() {
        let held = [entry(100, slack), entry(101, slack), entry(102, slack), entry(200, safari)]
        let plan = Plan(
            demote: [id(300): entry(300, safari), id(301): entry(301, safari), id(302): entry(302, safari)],
            restore: [id(100), id(101), id(102), id(200), id(150), id(151), id(152)]
        )
        let report = Evaluation.report(
            ledger: held,
            plan: plan,
            restoreResults: [
                id(100): .ok,
                id(101): .noSuchProcess,
                id(102): .failed(EINVAL),
                id(200): .notPermitted,
                id(150): .ok,
                id(151): .notPermitted,
                id(152): .failed(EIO),
            ],
            demoteResults: [id(300): .ok, id(301): .ok, id(302): .failed(EINVAL)]
        )
        #expect(report == Evaluation.PassReport(
            slowed: [safari: 2],
            givenBack: [slack: 1],
            inheritedGivenBack: 1,
            refused: [safari: 1],
            inheritedRefused: 1,
            // A held give-back and a demotion are both tried again; an inherited give-back
            // is not, since nothing leads a later pass back to it.
            failed: [EINVAL: 2],
            inheritedFailed: [EIO: 1]
        ))
    }

    @Test func anEmptyPassReportsNothing() {
        let report = Evaluation.report(ledger: [], plan: Plan(), restoreResults: [:], demoteResults: [:])
        #expect(report == Evaluation.PassReport())
    }

    // MARK: - Order

    @Test func processesAreVisitedInPIDOrder() {
        let later = ProcessIdentity(pid: 100, startSec: 5, startUsec: 0)
        let earlier = ProcessIdentity(pid: 100, startSec: 4, startUsec: 0)
        #expect(Evaluation.ordered([id(300), later, id(20), earlier]) == [id(20), earlier, later, id(300)])
    }
}
