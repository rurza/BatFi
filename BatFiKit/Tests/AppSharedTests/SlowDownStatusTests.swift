//
//  SlowDownStatusTests.swift
//  BatFi
//
//  Unit tests for what the menu says about each app slowed down on battery: whether BatFi
//  is slowing it right now, and if not, why.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SlowDownStatusTests {
    private typealias Status = SlowDownStatus
    private typealias Reason = SlowDownStatus.Reason

    private let me: UInt32 = 501
    private let root: UInt32 = 0
    private let batFiPID: Int32 = 900

    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"
    private let batFi = "software.micropixels.BatFi"

    // MARK: - The Mac

    private func id(_ pid: Int32) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startSec: 1_700_000_000 + UInt64(pid), startUsec: 250)
    }

    private func process(_ pid: Int32, parent ppid: Int32 = 1, uid: UInt32? = nil, coalition: UInt64?) -> ProcessRecord {
        ProcessRecord(identity: id(pid), ppid: ppid, uid: uid ?? me, coalitionID: coalition)
    }

    /// Slack (coalition 10) with two helpers, Safari (coalition 20) with its WebContent.
    private var world: [ProcessRecord] {
        [
            process(1, parent: 0, uid: root, coalition: 1),
            process(batFiPID, coalition: 90),
            process(100, coalition: 10),
            process(101, parent: 100, coalition: 10),
            process(102, parent: 1, coalition: 10),
            process(200, coalition: 20),
            process(201, parent: 1, coalition: 20),
        ]
    }

    private func running(_ bundleID: String, _ pid: Int32, eligible: Bool = true) -> RunningAppRecord {
        RunningAppRecord(bundleID: bundleID, pid: pid, isEligible: eligible, isRegular: true)
    }

    private var apps: [RunningAppRecord] {
        [
            running(slack, 100),
            running(safari, 200),
            RunningAppRecord(bundleID: batFi, pid: batFiPID, isEligible: false, isRegular: false),
        ]
    }

    private func entry(_ pid: Int32, _ bundleID: String, coalition: UInt64 = 10) -> ThrottleLedgerEntry {
        ThrottleLedgerEntry(identity: id(pid), bundleID: bundleID, coalitionID: coalition)
    }

    /// What a pass planned from: active, Slack slowed in the background, nothing in front.
    private func planned(
        active: Bool = true,
        slowed: [String: SlowDownMode],
        apps: [RunningAppRecord]? = nil,
        frontmostPID: Int32? = nil,
        frontmostBundleID: String? = nil,
        recentlyActive: Set<String> = [],
        audio: Set<Int32> = [],
        quitting: Set<String> = []
    ) -> BackgroundThrottlePolicy.Input {
        BackgroundThrottlePolicy.Input(
            isActive: active,
            slowedApps: slowed,
            runningApps: apps ?? self.apps,
            processes: world,
            frontmostPID: frontmostPID,
            frontmostBundleID: frontmostBundleID,
            recentlyActiveBundleIDs: recentlyActive,
            audioActivePIDs: audio,
            quittingBundleIDs: quitting,
            currentUID: me,
            ownPID: batFiPID,
            ledger: [],
            unmanageable: []
        )
    }

    /// The statuses after a pass on battery that planned from `planned`, unless told otherwise.
    private func statuses(
        slowed: [String: SlowDownMode]? = nil,
        isEnabled: Bool = true,
        licence: Status.Licence = .valid,
        onBattery: Bool = true,
        batteryIsSettled: Bool = true,
        runningApps: [RunningAppRecord]?? = nil,
        planned: BackgroundThrottlePolicy.Input?? = nil,
        refused: Set<ProcessIdentity> = [],
        ledger: [ThrottleLedgerEntry] = []
    ) -> [String: Status] {
        let slowed = slowed ?? [slack: .backgroundOnly]
        let planned = planned ?? self.planned(slowed: slowed)
        return Status.statuses(Status.Input(
            slowedApps: slowed,
            isEnabled: isEnabled,
            licence: licence,
            onBattery: onBattery,
            batteryIsSettled: batteryIsSettled,
            runningApps: runningApps ?? planned?.runningApps,
            planned: planned,
            refused: refused,
            ledger: ledger
        ))
    }

    private func reason(_ statuses: [String: Status], _ bundleID: String) -> Reason?? {
        guard case let .notSlowed(reason)? = statuses[bundleID] else { return .none }
        return .some(reason)
    }

    // MARK: - Slowed

    @Test func anAppIsSlowedWhileTheLedgerHoldsAnyOfItsProcesses() {
        let result = statuses(ledger: [entry(101, slack)])

        #expect(result == [slack: .slowed])
    }

    /// A give-back the kernel failed leaves the process slowed on the charger until a later
    /// pass manages it: what the menu says follows what is true, not what BatFi wants.
    @Test func anAppStillHeldOnTheChargerIsSlowed() {
        let result = statuses(onBattery: false, planned: .some(nil), ledger: [entry(100, slack)])

        #expect(result[slack] == .slowed)
    }

    /// One status per app in the list, whatever else runs or is held.
    @Test func everyAppInTheListGetsAStatusAndNoOtherDoes() {
        let result = statuses(slowed: [slack: .backgroundOnly, safari: .always], ledger: [entry(200, safari, coalition: 20)])

        #expect(Set(result.keys) == [slack, safari])
        #expect(result[safari] == .slowed)
    }

    // MARK: - Nothing may be slowed

    @Test func withoutAValidLicenceNothingIsSlowedForThatReasonFirst() {
        let result = statuses(licence: .invalid, onBattery: false, planned: .some(nil))

        #expect(reason(result, slack) == .some(.licence))
    }

    @Test func onTheChargerTheChargerIsTheReasonBeforeTheSettleWait() {
        let result = statuses(onBattery: false, batteryIsSettled: false, planned: .some(nil))

        #expect(reason(result, slack) == .some(.charger))
    }

    @Test func justUnpluggedTheSettleWaitIsTheReason() {
        let result = statuses(batteryIsSettled: false, planned: .some(nil))

        #expect(reason(result, slack) == .some(.justUnplugged))
    }

    /// Being on the charger outranks anything about the app itself.
    @Test func theChargerOutranksTheAppBeingInUse() {
        let result = statuses(onBattery: false, planned: planned(slowed: [slack: .backgroundOnly], frontmostPID: 100, frontmostBundleID: slack))

        #expect(reason(result, slack) == .some(.charger))
    }

    /// The licence is not read yet: nothing is slowed, but "not active" would be untrue.
    @Test func aLicenceNotReadYetGivesNoReason() {
        let result = statuses(licence: .unknown, planned: .some(nil))

        #expect(reason(result, slack) == .some(nil))
    }

    /// With the switch off the menu offers no button, so there is nothing to explain.
    @Test func withTheSwitchOffNoReasonIsGiven() {
        let result = statuses(isEnabled: false, planned: .some(nil))

        #expect(reason(result, slack) == .some(nil))
    }

    // MARK: - The app

    @Test func anAppThatIsNotRunningIsNotSlowedForThatReason() {
        let result = statuses(slowed: [slack: .backgroundOnly, "com.example.absent": .always])

        #expect(reason(result, "com.example.absent") == .some(.notRunning))
    }

    /// A pass that found no slowed app running reads no process table and plans nothing.
    @Test func withNoSlowedAppRunningAndNothingPlannedTheAppIsNotRunning() {
        let result = statuses(runningApps: .some(apps.filter { $0.bundleID != slack }), planned: .some(nil))

        #expect(reason(result, slack) == .some(.notRunning))
    }

    /// Running, but not as an app BatFi slows — one without a Dock icon now, say. "Isn't
    /// running" would be untrue.
    @Test func anAppRunningOnlyAsAnIneligibleInstanceGivesNoReason() {
        let apps = [running(slack, 100, eligible: false), running(safari, 200)]
        let result = statuses(planned: planned(slowed: [slack: .backgroundOnly], apps: apps))

        #expect(reason(result, slack) == .some(nil))
    }

    @Test func aBackgroundOnlyAppInFrontIsInUse() {
        let result = statuses(planned: planned(slowed: [slack: .backgroundOnly], frontmostPID: 100, frontmostBundleID: slack))

        #expect(reason(result, slack) == .some(.inUse))
    }

    /// Its grace after leaving the front: the user was using it a moment ago.
    @Test func aBackgroundOnlyAppJustLeftInFrontIsInUse() {
        let result = statuses(planned: planned(slowed: [slack: .backgroundOnly], recentlyActive: [slack]))

        #expect(reason(result, slack) == .some(.inUse))
    }

    /// Something else in its coalition is in front.
    @Test func aBackgroundOnlyAppWhoseCoalitionIsInFrontIsInUse() {
        let result = statuses(planned: planned(slowed: [slack: .backgroundOnly], frontmostPID: 102, frontmostBundleID: "com.example.companion"))

        #expect(reason(result, slack) == .some(.inUse))
    }

    /// "Always" is slowed while in use too, so being in front is no reason; the pass slowed
    /// it, and only the ledger would not say so if the kernel failed.
    @Test func anAlwaysAppInFrontIsNotInUseForThisPurpose() {
        let slowed: [String: SlowDownMode] = [slack: .always]
        let result = statuses(slowed: slowed, planned: planned(slowed: slowed, frontmostPID: 100, frontmostBundleID: slack))

        #expect(reason(result, slack) == .some(nil))
    }

    @Test(arguments: [SlowDownMode.backgroundOnly, .always])
    func anAppWhoseCoalitionPlaysAudioIsNotSlowedForThatReason(mode: SlowDownMode) {
        let slowed = [slack: mode]
        let result = statuses(slowed: slowed, planned: planned(slowed: slowed, audio: [102]))

        #expect(reason(result, slack) == .some(.audio))
    }

    @Test(arguments: [SlowDownMode.backgroundOnly, .always])
    func anAppAskedToQuitIsNotSlowedForThatReason(mode: SlowDownMode) {
        let slowed = [slack: mode]
        let result = statuses(slowed: slowed, planned: planned(slowed: slowed, quitting: [slack]))

        #expect(reason(result, slack) == .some(.quitting))
    }

    @Test func anAppTheKernelRefusedIsNotSlowedForThatReason() {
        let result = statuses(refused: [id(101)])

        #expect(reason(result, slack) == .some(.refused))
    }

    // MARK: - Priority

    @Test func inUseOutranksAudioWhichOutranksQuitting() {
        let slowed: [String: SlowDownMode] = [slack: .backgroundOnly]
        let all = statuses(
            planned: planned(slowed: slowed, frontmostPID: 100, frontmostBundleID: slack, audio: [101], quitting: [slack]),
            refused: [id(101)]
        )
        let audioAndQuit = statuses(planned: planned(slowed: slowed, audio: [101], quitting: [slack]), refused: [id(101)])
        let quitAndRefused = statuses(planned: planned(slowed: slowed, quitting: [slack]), refused: [id(101)])

        #expect(reason(all, slack) == .some(.inUse))
        #expect(reason(audioAndQuit, slack) == .some(.audio))
        #expect(reason(quitAndRefused, slack) == .some(.quitting))
    }

    /// Audio the pass could not read yet plans nothing to slow, and says nothing about the app.
    @Test func aPassThatMayNotSlowGivesNoReasonOnBattery() {
        let result = statuses(planned: planned(active: false, slowed: [slack: .backgroundOnly]))

        #expect(reason(result, slack) == .some(nil))
    }

    /// Nothing about the app spares it, nothing was refused, and still it is not held: a
    /// demotion that failed, to be tried again. No reason the menu could give is true.
    @Test func anAppNothingSparesThatIsNotHeldGivesNoReason() {
        #expect(reason(statuses(), slack) == .some(nil))
    }
}
