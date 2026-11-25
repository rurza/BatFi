//
//  BackgroundThrottlePolicyTests.swift
//  BatFi
//
//  Unit tests for the pure policy that decides which processes of the apps slowed on
//  battery BatFi demotes to the efficiency cores, and which it gives back.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct BackgroundThrottlePolicyTests {
    private typealias Policy = BackgroundThrottlePolicy
    private typealias Plan = BackgroundThrottlePolicy.Plan

    private let me: UInt32 = 501
    private let root: UInt32 = 0

    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"
    private let terminal = "com.apple.Terminal"
    private let batFi = "software.micropixels.BatFi"

    private let batFiPID: Int32 = 900

    // MARK: - The Mac

    /// Every process in these tests started at a time derived from its pid, so a pid that is
    /// reused later can be given a start time no living process has.
    private func id(_ pid: Int32, startedAt start: UInt64? = nil) -> ProcessIdentity {
        ProcessIdentity(pid: pid, startSec: start ?? 1_700_000_000 + UInt64(pid), startUsec: 250)
    }

    private func process(
        _ pid: Int32,
        parent ppid: Int32 = 1,
        uid: UInt32? = nil,
        coalition: UInt64?,
        startedAt start: UInt64? = nil
    ) -> ProcessRecord {
        ProcessRecord(identity: id(pid, startedAt: start), ppid: ppid, uid: uid ?? me, coalitionID: coalition)
    }

    /// Slack (coalition 10): the app, two helpers it spawned, a grandchild, and an
    /// app-bundled XPC service that launchd started (ppid 1) in the same coalition.
    private var slackProcesses: [ProcessRecord] {
        [
            process(100, coalition: 10),
            process(101, parent: 100, coalition: 10),
            process(102, parent: 100, coalition: 10),
            process(103, parent: 1, coalition: 10),
            process(104, parent: 101, coalition: 10),
        ]
    }

    private var slackPIDs: [Int32] { [100, 101, 102, 103, 104] }

    /// Safari (coalition 20) and a WebContent process.
    private var safariProcesses: [ProcessRecord] {
        [process(200, coalition: 20), process(201, parent: 1, coalition: 20)]
    }

    /// Terminal (coalition 30) and its shell.
    private var terminalProcesses: [ProcessRecord] {
        [process(300, coalition: 30), process(301, parent: 300, coalition: 30)]
    }

    private var world: [ProcessRecord] {
        [process(1, parent: 0, uid: root, coalition: 1), process(batFiPID, coalition: 90)]
            + slackProcesses + safariProcesses + terminalProcesses
    }

    /// A running app as `NSWorkspace` lists it. Regular apps are the ones with a Dock icon;
    /// accessory and prohibited ones include WebContent, open/save panels and menu-bar apps.
    private func running(_ bundleID: String, _ pid: Int32, eligible: Bool = true, regular: Bool = true) -> RunningAppRecord {
        RunningAppRecord(bundleID: bundleID, pid: pid, isEligible: eligible, isRegular: regular)
    }

    private var apps: [RunningAppRecord] {
        [
            running(slack, 100, eligible: true),
            running(safari, 200, eligible: true),
            running(terminal, 300, eligible: true),
            running(batFi, batFiPID, eligible: false, regular: false),
        ]
    }

    private func input(
        active: Bool = true,
        slowed: [String: SlowDownMode]? = nil,
        apps: [RunningAppRecord]? = nil,
        processes: [ProcessRecord]? = nil,
        frontmostPID: Int32? = nil,
        frontmostBundleID: String? = nil,
        recentlyActive: Set<String> = [],
        audio: Set<Int32> = [],
        quitting: Set<String> = [],
        ledger: [ThrottleLedgerEntry] = [],
        unmanageable: Set<ProcessIdentity> = []
    ) -> Policy.Input {
        Policy.Input(
            isActive: active,
            slowedApps: slowed ?? [slack: .backgroundOnly],
            runningApps: apps ?? self.apps,
            processes: processes ?? world,
            frontmostPID: frontmostPID,
            frontmostBundleID: frontmostBundleID,
            recentlyActiveBundleIDs: recentlyActive,
            audioActivePIDs: audio,
            quittingBundleIDs: quitting,
            currentUID: me,
            ownPID: batFiPID,
            ledger: ledger,
            unmanageable: unmanageable
        )
    }

    private func entry(_ pid: Int32, _ bundleID: String, coalition: UInt64?, startedAt start: UInt64? = nil) -> ThrottleLedgerEntry {
        ThrottleLedgerEntry(identity: id(pid, startedAt: start), bundleID: bundleID, coalitionID: coalition)
    }

    /// What the ledger looks like after an earlier pass demoted all of Slack.
    private var slackHeld: [ThrottleLedgerEntry] {
        slackPIDs.map { entry($0, slack, coalition: 10) }
    }

    private var safariHeld: [ThrottleLedgerEntry] {
        [entry(200, safari, coalition: 20), entry(201, safari, coalition: 20)]
    }

    private func ids(_ pids: [Int32]) -> Set<ProcessIdentity> {
        Set(pids.map { id($0) })
    }

    /// The ledger once every step of `plan` succeeded — what the next pass is handed.
    private func applying(_ plan: Plan, to ledger: [ThrottleLedgerEntry]) -> [ThrottleLedgerEntry] {
        ledger.filter { !plan.restore.contains($0.identity) && !plan.forget.contains($0.identity) }
            .map { plan.rerecord[$0.identity] ?? $0 }
            + plan.demote.values.sorted { $0.identity.pid < $1.identity.pid }
    }

    // MARK: - Nothing slowed

    /// Off the battery and with the master switch off both arrive as `isActive == false`; an
    /// empty set is what turning the last app's toggle off leaves. Either way BatFi holds
    /// nothing.
    @Test(arguments: [(false, true), (true, false)])
    func whenNothingIsToBeSlowedEveryLedgerEntryIsRestored(active: Bool, anythingSlowed: Bool) {
        let plan = Policy.plan(input(
            active: active,
            slowed: anythingSlowed ? [slack: .backgroundOnly, safari: .always] : [:],
            ledger: slackHeld + safariHeld
        ))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs + [200, 201]))
        #expect(plan.forget.isEmpty)
    }

    // MARK: - Demotion

    /// Helpers, grandchildren and the XPC service launchd started on the app's behalf all
    /// share its resource coalition, and none of them inherits a demotion made before it
    /// existed, so each is demoted on its own.
    @Test func aSlowedAppInTheBackgroundHasEveryProcessInItsCoalitionDemoted() {
        let plan = Policy.plan(input())

        #expect(Set(plan.demote.keys) == ids(slackPIDs))
        #expect(plan.demote[id(103)] == entry(103, slack, coalition: 10))
        #expect(plan.demote.values.allSatisfy { $0.bundleID == slack && $0.coalitionID == 10 })
        #expect(plan.restore.isEmpty)
        #expect(plan.forget.isEmpty)
    }

    @Test func aFrontmostBackgroundOnlyAppIsGivenBackEverything() {
        let plan = Policy.plan(input(frontmostPID: 100, frontmostBundleID: slack, ledger: slackHeld))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs))
    }

    /// The window in front belongs to another app with its own bundle ID, but that app runs
    /// in Slack's coalition — whatever the coalition does, it may be doing for the window in
    /// use. It is not even Slack's descendant here, only a coalition member. It is given back
    /// too: anything in the coalition can have inherited a demotion.
    @Test func aBackgroundOnlyAppIsLeftAloneWhileAnotherBundleInItsCoalitionIsFrontmost() {
        let companion = "com.example.companion"
        let plan = Policy.plan(input(
            apps: apps + [running(companion, 105, eligible: true)],
            processes: world + [process(105, parent: 1, coalition: 10)],
            frontmostPID: 105,
            frontmostBundleID: companion,
            ledger: slackHeld
        ))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs + [105]))
    }

    /// The same, where the app in front is an accessory one, so Slack's claim stays whole
    /// and only the frontmost pid being in the coalition spares it.
    @Test func aBackgroundOnlyAppIsLeftAloneWhileAnAccessoryAppInItsCoalitionIsFrontmost() {
        let companion = "com.example.companion"
        let plan = Policy.plan(input(
            apps: apps + [running(companion, 105, regular: false)],
            processes: world + [process(105, parent: 1, coalition: 10)],
            frontmostPID: 105,
            frontmostBundleID: companion,
            ledger: slackHeld
        ))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs + [105]))
    }

    /// The owner's decision: "Always" means while you use it too.
    @Test func aFrontmostAlwaysAppIsStillDemoted() {
        let plan = Policy.plan(input(slowed: [slack: .always], frontmostPID: 100, frontmostBundleID: slack))

        #expect(Set(plan.demote.keys) == ids(slackPIDs))
    }

    /// The grace after an app leaves the front absorbs Cmd-Tab cycling and the flap a
    /// status-item click causes; "Always" has no front to leave.
    @Test(arguments: [(SlowDownMode.backgroundOnly, false), (SlowDownMode.always, true)])
    func aRecentlyActiveAppIsSparedOnlyInBackgroundOnlyMode(mode: SlowDownMode, demoted: Bool) {
        let plan = Policy.plan(input(slowed: [slack: mode], recentlyActive: [slack]))

        #expect(Set(plan.demote.keys) == (demoted ? ids(slackPIDs) : []))
    }

    /// A demoted process loses its real-time threads, which is audible. The XPC service is
    /// the one playing here, and the whole coalition is spared: the app feeding it matters too.
    @Test(arguments: [SlowDownMode.backgroundOnly, .always])
    func aCoalitionPlayingOrRecordingAudioIsSparedAndGivenBack(mode: SlowDownMode) {
        let plan = Policy.plan(input(slowed: [slack: mode], audio: [103], ledger: slackHeld))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs))
    }

    // MARK: - Asked to quit

    /// A slowed app can be too starved to answer a quit, or the dialog it puts up — an
    /// "Always" one under load most of all. While it is asked, it is given back and left alone.
    @Test(arguments: [SlowDownMode.backgroundOnly, .always])
    func anAppAskedToQuitIsGivenBackAndSpared(mode: SlowDownMode) {
        let plan = Policy.plan(input(slowed: [slack: mode], quitting: [slack], ledger: slackHeld))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs))
    }

    /// Like audio, the whole coalition: another slowed app whose claim covers the quitting
    /// app's processes would otherwise slow them down again.
    @Test func anotherSlowedAppInTheCoalitionOfAnAppAskedToQuitIsSparedToo() {
        let companion = "com.example.companion"
        let plan = Policy.plan(input(
            slowed: [slack: .always, companion: .always],
            apps: apps + [running(companion, 105)],
            processes: world + [process(105, parent: 100, coalition: 10)],
            quitting: [slack]
        ))

        #expect(plan.demote.isEmpty)
    }

    @Test func anAppAskedToQuitSparesNoOtherApp() {
        let plan = Policy.plan(input(slowed: [slack: .always, safari: .always], quitting: [safari]))

        #expect(Set(plan.demote.keys) == ids(slackPIDs))
    }

    /// The exemption only ever takes an app out of what is slowed, so clearing it leaves
    /// nothing held that should not be: an app still running is slowed again by the usual
    /// rules, and one that has quit leaves nothing behind.
    @Test func whenTheExemptionEndsARunningAppIsSlowedAgainAndAQuitOneLeavesNothingHeld() {
        let spared = input(slowed: [slack: .always], quitting: [slack], ledger: slackHeld)
        let released = applying(Policy.plan(spared), to: spared.ledger)
        #expect(released.isEmpty)

        let stillRunning = Policy.plan(input(slowed: [slack: .always], ledger: released))
        #expect(Set(stillRunning.demote.keys) == ids(slackPIDs))

        let quit = Policy.plan(input(
            slowed: [slack: .always],
            apps: apps.filter { $0.bundleID != slack },
            processes: world.filter { !slackPIDs.contains($0.identity.pid) },
            ledger: released
        ))
        #expect(quit.isEmpty)
    }

    /// Quitting from the list is offered for apps that are not slowed too; being asked to
    /// quit gives nothing back that was not slowed, and slows nothing down.
    @Test func anAppAskedToQuitThatIsNotSlowedChangesNothing() {
        let plan = Policy.plan(input(slowed: [slack: .always], quitting: [terminal], ledger: slackHeld))

        #expect(plan.isEmpty)
    }

    /// Not slowed itself, but started from the shell of a Terminal that is, so it was slowed
    /// as part of Terminal's subtree. Asked to quit, it is given back all the same.
    @Test func anUnslowedAppSlowedAsPartOfAnotherIsGivenBackWhenAskedToQuit() {
        let tool = "com.example.tool"
        let toolApps = apps + [running(tool, 310)]
        let processes = world + [process(310, parent: 301, coalition: 30)]
        let held = applying(Policy.plan(input(slowed: [terminal: .always], apps: toolApps, processes: processes)), to: [])
        #expect(Set(held.map(\.identity)) == ids([300, 301, 310]))

        let plan = Policy.plan(input(
            slowed: [terminal: .always],
            apps: toolApps,
            processes: processes,
            quitting: [tool],
            ledger: held
        ))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids([300, 301, 310]))
    }

    // MARK: - Never touched

    @Test func aProcessOfAnotherUserIsNeverDemoted() {
        let plan = Policy.plan(input(processes: world + [process(106, parent: 100, uid: root, coalition: 10)]))

        #expect(Set(plan.demote.keys) == ids(slackPIDs))
    }

    /// Placed in Slack's coalition and owned by the user, so the pid alone keeps them out.
    @Test func launchdAndTheKernelAreNeverDemoted() {
        let processes = world.filter { $0.identity.pid != 1 } + [
            process(0, parent: 0, coalition: 10),
            process(1, parent: 0, coalition: 10),
        ]

        let plan = Policy.plan(input(processes: processes))

        #expect(Set(plan.demote.keys) == ids(slackPIDs))
    }

    /// An app launched from Xcode, say, next to a BatFi launched from Xcode. BatFi slowing
    /// itself down would slow down the very thing that has to give the cores back.
    @Test func aCoalitionBatFiRunsInIsNeverDemoted() {
        let processes = world.filter { $0.identity.pid != batFiPID } + [process(batFiPID, coalition: 10)]

        let plan = Policy.plan(input(processes: processes, ledger: slackHeld))

        #expect(plan.demote.isEmpty)
        #expect(plan.restore == ids(slackPIDs))
    }

    @Test func batFiIsNeverDemotedEvenAsADescendantOfAnAppWithoutACoalition() {
        let processes = world.filter { $0.identity.pid != batFiPID } + [
            process(500, coalition: nil),
            process(batFiPID, parent: 500, coalition: nil),
        ]
        let plan = Policy.plan(input(
            slowed: [slack: .backgroundOnly, "com.example.launcher": .backgroundOnly],
            apps: apps + [running("com.example.launcher", 500, eligible: true)],
            processes: processes
        ))

        #expect(Set(plan.demote.keys) == ids(slackPIDs))
    }

    /// A process the kernel refused once (EPERM) is not asked again.
    @Test func anUnmanageableProcessIsNeverDemoted() {
        let plan = Policy.plan(input(unmanageable: [id(102)]))

        #expect(Set(plan.demote.keys) == ids([100, 101, 103, 104]))
    }

    /// The manager marks each running app with `ThrottleEligibility`; a denylisted bundle
    /// that somehow sits in the slowed set is never acted on.
    @Test func aDenylistedBundleInTheSlowedSetIsNeverDemoted() {
        let finder = "com.apple.finder"
        let eligible = ThrottleEligibility.canOfferActions(
            bundleID: finder,
            bundleURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            ownBundleIDs: [batFi]
        )
        let plan = Policy.plan(input(
            slowed: [finder: .always],
            apps: apps + [running(finder, 400, eligible: eligible)],
            processes: world + [process(400, coalition: 40), process(401, parent: 400, coalition: 40)]
        ))

        #expect(plan.demote.isEmpty)
    }

    // MARK: - Which processes

    /// An app started from a shell shares Terminal's coalition. Terminal is not slowed, so
    /// only the app and what it spawned are — never Terminal, its shell, or the other job.
    @Test func inACoalitionSharedWithAnUnslowedAppOnlyTheSlowedAppsSubtreeIsDemoted() {
        let tool = "com.example.tool"
        let plan = Policy.plan(input(
            slowed: [tool: .backgroundOnly],
            apps: apps + [running(tool, 310, eligible: true)],
            processes: world + [
                process(302, parent: 301, coalition: 30),
                process(310, parent: 301, coalition: 30),
                process(311, parent: 310, coalition: 30),
                process(312, parent: 311, coalition: 30),
            ]
        ))

        #expect(Set(plan.demote.keys) == ids([310, 311, 312]))
        // Each is recorded with the coalition it runs in, so that whatever inherited its
        // demotion can still be found once it has exited.
        #expect(plan.demote.values.allSatisfy { $0.bundleID == tool && $0.coalitionID == 30 })
    }

    /// Safari's coalition holds its WebContent, Networking and GPU processes, which register
    /// as accessory apps with bundle IDs of their own. They are part of Safari, not another
    /// app sharing its coalition, so Safari is still slowed whole.
    @Test func accessoryAppsInTheCoalitionDoNotNarrowIt() {
        let plan = Policy.plan(input(
            slowed: [safari: .backgroundOnly],
            apps: apps + [running("com.apple.WebKit.WebContent", 201, regular: false)]
        ))

        #expect(Set(plan.demote.keys) == ids([200, 201]))
        #expect(plan.demote.values.allSatisfy { $0.coalitionID == 20 })
    }

    /// Nor does an open/save panel or QuickLook, which run as prohibited apps.
    @Test func aPanelServiceInTheCoalitionDoesNotNarrowIt() {
        let plan = Policy.plan(input(
            slowed: [safari: .backgroundOnly],
            apps: apps + [running("com.apple.appkit.xpc.openAndSavePanelService", 202, eligible: false, regular: false)],
            processes: world + [process(202, parent: 1, coalition: 20)]
        ))

        #expect(Set(plan.demote.keys) == ids([200, 201, 202]))
    }

    /// Both apps are slowed, so neither narrows the other: the coalition is demoted whole,
    /// each process once, and attributed the same way on every pass.
    @Test func twoSlowedAppsInOneCoalitionAreDemotedWholeAndSettle() {
        let companion = "com.example.companion"
        let first = input(
            slowed: [slack: .backgroundOnly, companion: .backgroundOnly],
            apps: apps + [running(companion, 105)],
            processes: world + [process(105, parent: 100, coalition: 10)]
        )

        let plan = Policy.plan(first)

        #expect(Set(plan.demote.keys) == ids(slackPIDs + [105]))
        #expect(plan.demote.values.allSatisfy { $0.coalitionID == 10 })

        var second = first
        second.ledger = applying(plan, to: first.ledger)
        #expect(Policy.plan(second).isEmpty)
    }

    /// When the coalition cannot be read, the app and the processes it spawned are still
    /// covered; an unrelated process that also has no coalition is not.
    @Test func withoutACoalitionTheAppAndItsDescendantsAreDemoted() {
        let app = "com.example.nocoalition"
        let plan = Policy.plan(input(
            slowed: [app: .backgroundOnly],
            apps: apps + [running(app, 500, eligible: true)],
            processes: world + [
                process(500, coalition: nil),
                process(501, parent: 500, coalition: nil),
                process(502, parent: 501, coalition: nil),
                process(503, parent: 1, coalition: nil),
            ]
        ))

        #expect(Set(plan.demote.keys) == ids([500, 501, 502]))
        #expect(plan.demote.values.allSatisfy { $0.bundleID == app && $0.coalitionID == nil })
    }

    @Test func everyInstanceOfASlowedBundleIsDemoted() {
        let plan = Policy.plan(input(
            apps: apps + [running(slack, 150, eligible: true)],
            processes: world + [process(150, coalition: 15), process(151, parent: 150, coalition: 15)]
        ))

        #expect(Set(plan.demote.keys) == ids(slackPIDs + [150, 151]))
        #expect(plan.demote[id(151)]?.coalitionID == 15)
    }

    /// "Background only" is about the app, not one of its windows' processes.
    @Test func noInstanceOfAFrontmostBackgroundOnlyBundleIsDemoted() {
        let plan = Policy.plan(input(
            apps: apps + [running(slack, 150, eligible: true)],
            processes: world + [process(150, coalition: 15), process(151, parent: 150, coalition: 15)],
            frontmostPID: 100,
            frontmostBundleID: slack
        ))

        #expect(plan.demote.isEmpty)
    }

    // MARK: - Over time

    @Test func aNewHelperIsTheOnlyProcessDemotedOnTheNextPass() {
        let first = input()
        let ledger = applying(Policy.plan(first), to: first.ledger)

        let plan = Policy.plan(input(processes: world + [process(107, parent: 100, coalition: 10)], ledger: ledger))

        #expect(Set(plan.demote.keys) == [id(107)])
        #expect(plan.restore.isEmpty)
        #expect(plan.forget.isEmpty)
    }

    /// Once a plan has been carried out, the same Mac asks for nothing more.
    @Test func aSecondPassOnTheSameMacIsEmpty() {
        let tool = "com.example.tool"
        let sharedCoalition = world + [process(310, parent: 301, coalition: 30), process(311, parent: 310, coalition: 30)]
        let inherited = world + [process(108, parent: 101, coalition: 10)]
        let cases: [(String, (([ThrottleLedgerEntry]) -> Policy.Input))] = [
            ("slowed in the background", { input(ledger: $0) }),
            ("frontmost", { input(frontmostPID: 100, frontmostBundleID: slack, ledger: $0) }),
            ("asked to quit", { input(slowed: [slack: .always], quitting: [slack], ledger: $0) }),
            ("not active", { input(active: false, ledger: $0) }),
            ("removed, with an inherited child", { input(slowed: [:], processes: inherited, ledger: $0) }),
            ("shared coalition", {
                input(
                    slowed: [tool: .always],
                    apps: apps + [running(tool, 310, eligible: true)],
                    processes: sharedCoalition,
                    ledger: $0
                )
            }),
        ]

        for (name, makeInput) in cases {
            // Start from Slack held, as a previous pass on battery would leave it.
            let first = makeInput(slackHeld)
            let ledger = applying(Policy.plan(first), to: first.ledger)

            let second = Policy.plan(makeInput(ledger))

            #expect(second.isEmpty, "\(name): \(second)")
        }
    }

    /// Children spawned after a demotion inherit it, and restoring the parent does not undo
    /// theirs, so letting go of an app gives back every process in its coalition — including
    /// the one that was never in the ledger. Safari, still slowed, keeps its demotion.
    @Test func removingAnAppGivesBackOnlyItsProcessesIncludingOnesThatInheritedTheDemotion() {
        let plan = Policy.plan(input(
            slowed: [safari: .backgroundOnly],
            processes: world + [process(108, parent: 101, coalition: 10)],
            ledger: slackHeld + safariHeld
        ))

        #expect(plan.restore == ids(slackPIDs + [108]))
        #expect(plan.demote.isEmpty)
        #expect(plan.forget.isEmpty)
    }

    /// Without a coalition to release, the inherited processes are found by walking down
    /// from the app. The child is in the ledger too; the walk covers it once.
    @Test func removingAnAppWithoutACoalitionGivesBackItsDescendants() {
        let app = "com.example.nocoalition"
        let plan = Policy.plan(input(
            slowed: [:],
            processes: world + [
                process(500, coalition: nil),
                process(501, parent: 500, coalition: nil),
                process(502, parent: 501, coalition: nil),
                process(503, parent: 1, coalition: nil),
            ],
            ledger: [entry(501, app, coalition: nil), entry(500, app, coalition: nil)]
        ))

        #expect(plan.restore == ids([500, 501, 502]))
    }

    /// The reviewer's case. Terminal and a tool started from its shell are both slowed, so
    /// their shared coalition is demoted whole, and a build the shell starts inherits it
    /// before any pass records it. Un-slowing Terminal narrows the tool to its own subtree —
    /// and the build, still in the coalition, has to be given back then, and again once the
    /// tool exits.
    @Test func unslowingTerminalGivesBackABuildThatInheritedItsDemotion() {
        let tool = "com.example.tool"
        let toolApps = apps + [running(tool, 310)]
        let withTool = world + [process(310, parent: 301, coalition: 30)]
        let withBuild = withTool + [process(320, parent: 301, coalition: 30)]

        let bothSlowed = input(slowed: [terminal: .always, tool: .always], apps: toolApps, processes: withTool)
        let first = Policy.plan(bothSlowed)
        #expect(Set(first.demote.keys) == ids([300, 301, 310]))

        // The build starts, inheriting the demotion; then Terminal is un-slowed.
        let narrowed = input(slowed: [tool: .always], apps: toolApps, processes: withBuild, ledger: applying(first, to: []))
        let second = Policy.plan(narrowed)
        #expect(second.restore == ids([300, 301, 320]))
        #expect(second.demote.isEmpty)
        // The tool stays demoted, now on its own account.
        #expect(second.rerecord == [id(310): entry(310, tool, coalition: 30)])

        // The tool exits.
        let exited = input(
            slowed: [tool: .always],
            apps: apps,
            processes: withBuild.filter { $0.identity.pid != 310 },
            ledger: applying(second, to: narrowed.ledger)
        )
        let third = Policy.plan(exited)
        #expect(third.forget == [id(310)])
        #expect(third.restore.contains(id(320)))

        var settled = exited
        settled.ledger = applying(third, to: exited.ledger)
        #expect(settled.ledger.isEmpty)
        #expect(Policy.plan(settled).isEmpty)
    }

    /// A child the narrowed tool spawned inherits its demotion, and is reparented to launchd
    /// when the tool exits before any pass records the child. It is found through the
    /// coalition the tool's entry recorded.
    @Test func aChildOrphanedWhenANarrowedAppExitsIsGivenBack() {
        let tool = "com.example.tool"
        let plan = Policy.plan(input(
            slowed: [tool: .always],
            apps: apps,
            processes: world + [process(321, parent: 1, coalition: 30)],
            ledger: [entry(310, tool, coalition: 30)]
        ))

        #expect(plan.forget == [id(310)])
        #expect(plan.restore.contains(id(321)))
    }

    /// Reparented to launchd while the narrowed tool still runs, the child is outside its
    /// subtree, but still in its coalition.
    @Test func aReparentedChildOfANarrowedAppIsGivenBackWhenTheAppIsUnslowed() {
        let tool = "com.example.tool"
        let plan = Policy.plan(input(
            slowed: [:],
            apps: apps + [running(tool, 310)],
            processes: world + [process(310, parent: 301, coalition: 30), process(321, parent: 1, coalition: 30)],
            ledger: [entry(310, tool, coalition: 30)]
        ))

        #expect(plan.restore.contains(id(321)))
    }

    /// The app was demoted while its coalition could not be read. It can be now, and a child
    /// reparented to launchd is found through it.
    @Test func aReparentedChildIsGivenBackThroughACoalitionThatBecameReadable() {
        let app = "com.example.nocoalition"
        let plan = Policy.plan(input(
            slowed: [:],
            processes: world + [process(500, coalition: 50), process(505, parent: 1, coalition: 50)],
            ledger: [entry(500, app, coalition: nil)]
        ))

        #expect(plan.restore == ids([500, 505]))
    }

    /// Still slowed, and now readable: the entry is re-recorded with the coalition, without
    /// demoting the process again.
    @Test func anEntryIsReRecordedWhenItsCoalitionBecomesReadable() {
        let app = "com.example.nocoalition"
        let plan = Policy.plan(input(
            slowed: [app: .backgroundOnly],
            apps: apps + [running(app, 500)],
            processes: world + [process(500, coalition: 50)],
            ledger: [entry(500, app, coalition: nil)]
        ))

        #expect(plan.demote.isEmpty)
        #expect(plan.rerecord == [id(500): entry(500, app, coalition: 50)])
    }

    /// Coalition IDs start over at every boot. An entry left from before this boot — BatFi
    /// crashed, then the Mac restarted — names a coalition that is now somebody else's.
    @Test func anEntryFromBeforeThisBootReleasesNothing() {
        let plan = Policy.plan(input(
            active: false,
            ledger: [entry(4242, slack, coalition: 10, startedAt: 1_600_000_000)]
        ))

        #expect(plan.forget == [id(4242, startedAt: 1_600_000_000)])
        #expect(plan.restore.isEmpty)
    }

    /// Releasing a coalition gives back only what BatFi could have demoted.
    @Test func releasingACoalitionLeavesOtherUsersAndUnmanageableProcessesAlone() {
        let plan = Policy.plan(input(
            active: false,
            processes: world + [process(106, parent: 100, uid: root, coalition: 10), process(108, parent: 101, coalition: 10)],
            ledger: slackHeld,
            unmanageable: [id(108)]
        ))

        #expect(plan.restore == ids(slackPIDs))
    }

    /// The pid now belongs to a different process. Restoring it would touch something BatFi
    /// never demoted; the entry is simply dropped.
    @Test func aLedgerEntryWhosePidWasReusedIsForgottenNotRestored() {
        let reused = process(102, parent: 1, coalition: 77, startedAt: 1_800_000_000)
        let plan = Policy.plan(input(
            active: false,
            processes: world.filter { $0.identity.pid != 102 } + [reused],
            ledger: slackHeld
        ))

        #expect(plan.forget == [id(102)])
        #expect(!plan.restore.contains(reused.identity))
        #expect(plan.restore == ids([100, 101, 103, 104]))
    }

    @Test func aLedgerEntryWhoseProcessExitedIsForgotten() {
        let plan = Policy.plan(input(
            processes: world.filter { $0.identity.pid != 104 },
            ledger: slackHeld
        ))

        #expect(plan.forget == [id(104)])
        #expect(plan.restore.isEmpty)
        #expect(plan.demote.isEmpty)
    }

    /// A process table that came back empty is a failed read, not a Mac with nothing
    /// running. Forgetting the ledger on it would lose the only record of what to give back.
    @Test func anEmptyProcessTableForgetsNothing() {
        let plan = Policy.plan(input(active: false, processes: [], ledger: slackHeld))

        #expect(plan.isEmpty)
    }

    /// Nor is a table BatFi itself is missing from: it is partial, and what else it misses
    /// cannot be told from what has exited.
    @Test func aProcessTableWithoutBatFiForgetsNothing() {
        let partial = world.filter { ![batFiPID, 104].contains($0.identity.pid) }

        let plan = Policy.plan(input(processes: partial, ledger: slackHeld))

        #expect(plan.isEmpty)
    }

    // MARK: - After a crash

    @Test func launchReconcileRestoresTheLedgerAndEverythingItsCoalitionsStillRun() {
        let ledger = [entry(100, slack, coalition: 10), entry(101, slack, coalition: 10), entry(500, "com.example.nocoalition", coalition: nil), entry(777, slack, coalition: 10)]
        let processes = world + [
            process(106, parent: 100, uid: root, coalition: 10),
            process(108, parent: 101, coalition: 10),
            process(500, coalition: nil),
            process(501, parent: 500, coalition: nil),
            process(502, parent: 501, coalition: nil),
        ]

        let reconciled = Policy.reconcileAtLaunch(ledger: ledger, processes: processes, currentUID: me, ownPID: batFiPID)

        #expect(reconciled.restore == ids(slackPIDs + [108, 500, 501, 502]))
        #expect(reconciled.forget == [id(777)])
    }

    /// The crash left only exited entries; what inherited from them is still found.
    @Test func launchReconcileGivesBackWhatInheritedFromAnExitedEntry() {
        let reconciled = Policy.reconcileAtLaunch(
            ledger: [entry(777, slack, coalition: 10)],
            processes: world,
            currentUID: me,
            ownPID: batFiPID
        )

        #expect(reconciled.restore == ids(slackPIDs))
        #expect(reconciled.forget == [id(777)])
    }

    @Test(arguments: [false, true])
    func launchReconcileOnAFailedReadForgetsNothing(empty: Bool) {
        let processes = empty ? [] : world.filter { $0.identity.pid != batFiPID }

        let reconciled = Policy.reconcileAtLaunch(ledger: slackHeld, processes: processes, currentUID: me, ownPID: batFiPID)

        #expect(reconciled.restore.isEmpty)
        #expect(reconciled.forget.isEmpty)
    }

    // MARK: - Persistence

    /// The ledger outlives the process, and the mode is stored by its raw value.
    @Test func aLedgerEntryAndAModeSurviveAPersistenceRoundTrip() throws {
        let entries = [entry(100, slack, coalition: 10), entry(500, "com.example.nocoalition", coalition: nil)]

        let decoded = try JSONDecoder().decode([ThrottleLedgerEntry].self, from: JSONEncoder().encode(entries))

        #expect(decoded == entries)
        #expect(SlowDownMode.backgroundOnly.rawValue == "backgroundOnly")
        #expect(SlowDownMode.always.rawValue == "always")
    }
}
