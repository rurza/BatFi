//
//  BackgroundThrottlePolicy.swift
//  BatFi
//
//  Which processes of the apps the user slows down on battery BatFi confines to the
//  efficiency cores, and which it gives back.
//

import Foundation

/// How much of the time an app the user slows down on battery is slowed.
public enum SlowDownMode: String, Codable, CaseIterable, Sendable {
    /// Only while the app is not the one in use: given back the moment it comes to the front.
    case backgroundOnly
    /// Whenever the Mac is on battery, including while the app is in use. A demoted process
    /// can get no CPU at all while other work keeps the Mac busy, its interface included;
    /// the owner accepts that for this mode.
    case always
}

/// One process, told apart from any later process that is handed the same pid.
///
/// A pid alone is not enough to hold on to: pids are reused, and BatFi keeps its ledger
/// across launches. Restoring a pid that now belongs to something else would touch a
/// process BatFi never demoted.
public struct ProcessIdentity: Hashable, Codable, Sendable {
    public let pid: Int32
    /// The process's start time, as the kernel reports it.
    public let startSec: UInt64
    public let startUsec: UInt64

    public init(pid: Int32, startSec: UInt64, startUsec: UInt64) {
        self.pid = pid
        self.startSec = startSec
        self.startUsec = startUsec
    }

    func started(before other: ProcessIdentity) -> Bool {
        (startSec, startUsec) < (other.startSec, other.startUsec)
    }
}

/// One row of the process table.
public struct ProcessRecord: Hashable, Sendable {
    public let identity: ProcessIdentity
    public let ppid: Int32
    public let uid: UInt32
    /// The process's resource coalition, or nil where it could not be read.
    public let coalitionID: UInt64?

    public init(identity: ProcessIdentity, ppid: Int32, uid: UInt32, coalitionID: UInt64?) {
        self.identity = identity
        self.ppid = ppid
        self.uid = uid
        self.coalitionID = coalitionID
    }

    var pid: Int32 { identity.pid }
}

/// One running instance of an app, as `NSWorkspace` lists it.
public struct RunningAppRecord: Hashable, Sendable {
    public let bundleID: String
    public let pid: Int32
    /// What `ThrottleEligibility.canOfferActions` says about it.
    public let isEligible: Bool
    /// Whether its activation policy is `.regular` — an app with a Dock icon. Accessory and
    /// prohibited "apps" are mostly parts of another app: Safari's WebContent, Networking and
    /// GPU processes, Chrome's and Electron apps' helpers, open/save panels, QuickLook.
    public let isRegular: Bool

    public init(bundleID: String, pid: Int32, isEligible: Bool, isRegular: Bool) {
        self.bundleID = bundleID
        self.pid = pid
        self.isEligible = isEligible
        self.isRegular = isRegular
    }
}

/// A process BatFi demoted and has not yet given back.
///
/// There is no way to ask the kernel whether a process is demoted — the readback always
/// answers 0 — so the persisted ledger of these is the only record of what BatFi has to
/// give back, including after a crash.
public struct ThrottleLedgerEntry: Hashable, Codable, Sendable {
    public let identity: ProcessIdentity
    /// The slowed app the process was demoted for.
    public let bundleID: String
    /// The process's own resource coalition, or nil where it could not be read. Giving the
    /// entry back releases this coalition — which is how processes that inherited the
    /// demotion are still found once this one has exited.
    public let coalitionID: UInt64?

    public init(identity: ProcessIdentity, bundleID: String, coalitionID: UInt64?) {
        self.identity = identity
        self.bundleID = bundleID
        self.coalitionID = coalitionID
    }
}

/// Decides, from one snapshot of the Mac, which processes to demote to the efficiency cores
/// (`setpriority(PRIO_DARWIN_PROCESS, pid, PRIO_DARWIN_BG)`), which to give back, and what
/// to change in the ledger.
///
/// **Who.** Every process of a slowed app: its whole resource coalition — helpers,
/// grandchildren, and the XPC services launchd starts for it, which share the coalition but
/// not the app's process tree. Only processes BatFi's user owns, never launchd or the
/// kernel, never BatFi, and never one the kernel already refused.
///
/// **Narrowed** to the app and its descendants when its coalition cannot be read, or when
/// the coalition also runs another *regular* app that is not slowed — an app started from a
/// shell shares Terminal's coalition, and slowing it must not slow Terminal. Accessory and
/// prohibited apps in the coalition are the app's own parts and do not narrow it.
///
/// **Spared**, in either mode, while anything in the coalition plays or records audio (a
/// demoted process loses its real-time threads), while it runs an app the high-energy list
/// has just asked to quit (a starved app cannot answer), or the coalition is BatFi's own. In
/// `backgroundOnly` mode also while the app, or anything in its coalition, is frontmost, and
/// while it was frontmost a moment ago. The spared checks look at the whole coalition even
/// when only the app's descendants would be demoted: whatever the coalition is doing for the
/// window in front, or for the sound, the app may be part of.
///
/// **Given back.** Children spawned after a demotion inherit it, and restoring a parent does
/// not restore them, so giving back an entry is not enough: every entry that is let go —
/// given back, or forgotten because its process exited — releases its coalition, and a
/// running one its descendants too. Everything found that way is restored unless it stays
/// demoted. Restoring a process that is not demoted is harmless.
///
/// Carrying out a plan and running this again on the same Mac yields an empty plan.
public enum BackgroundThrottlePolicy {
    public struct Input: Sendable {
        /// The master switch is on, the app licence is valid, and the Mac is on battery: see
        /// `BackgroundThrottleEvaluation.isActive`.
        public var isActive: Bool
        public var slowedApps: [String: SlowDownMode]
        /// Every running app, whatever its activation policy; the policy tells them apart by
        /// `isEligible` and `isRegular`.
        public var runningApps: [RunningAppRecord]
        /// The whole process table. It must be complete: one missing BatFi's own process is
        /// taken as a failed read and nothing is planned, but a table missing other rows
        /// would have their ledger entries forgotten as exited.
        public var processes: [ProcessRecord]
        public var frontmostPID: Int32?
        public var frontmostBundleID: String?
        /// Apps that left the front too recently to be demoted again.
        public var recentlyActiveBundleIDs: Set<String>
        public var audioActivePIDs: Set<Int32>
        /// Apps the high-energy list has just asked to quit; see `QuitExemptions`.
        public var quittingBundleIDs: Set<String>
        public var currentUID: UInt32
        public var ownPID: Int32
        public var ledger: [ThrottleLedgerEntry]
        /// Processes the kernel refused to demote.
        public var unmanageable: Set<ProcessIdentity>

        public init(
            isActive: Bool,
            slowedApps: [String: SlowDownMode],
            runningApps: [RunningAppRecord],
            processes: [ProcessRecord],
            frontmostPID: Int32?,
            frontmostBundleID: String?,
            recentlyActiveBundleIDs: Set<String>,
            audioActivePIDs: Set<Int32>,
            quittingBundleIDs: Set<String>,
            currentUID: UInt32,
            ownPID: Int32,
            ledger: [ThrottleLedgerEntry],
            unmanageable: Set<ProcessIdentity>
        ) {
            self.isActive = isActive
            self.slowedApps = slowedApps
            self.runningApps = runningApps
            self.processes = processes
            self.frontmostPID = frontmostPID
            self.frontmostBundleID = frontmostBundleID
            self.recentlyActiveBundleIDs = recentlyActiveBundleIDs
            self.audioActivePIDs = audioActivePIDs
            self.quittingBundleIDs = quittingBundleIDs
            self.currentUID = currentUID
            self.ownPID = ownPID
            self.ledger = ledger
            self.unmanageable = unmanageable
        }
    }

    public struct Plan: Equatable, Sendable {
        /// The processes to demote, each with the ledger entry to record once it is.
        public var demote: [ProcessIdentity: ThrottleLedgerEntry]
        /// Processes already demoted and staying so, whose ledger entry is to be replaced
        /// without touching the process: the app it counts against changed, or its
        /// coalition could not be read before and can now.
        public var rerecord: [ProcessIdentity: ThrottleLedgerEntry]
        /// The processes to give back: alive ledger entries, and processes that inherited a
        /// demotion without ever being in the ledger. Their ledger entries go once restored.
        public var restore: Set<ProcessIdentity>
        /// Ledger entries whose process has exited, or whose pid now belongs to another one.
        /// Dropped without touching them.
        public var forget: Set<ProcessIdentity>

        public init(
            demote: [ProcessIdentity: ThrottleLedgerEntry] = [:],
            rerecord: [ProcessIdentity: ThrottleLedgerEntry] = [:],
            restore: Set<ProcessIdentity> = [],
            forget: Set<ProcessIdentity> = []
        ) {
            self.demote = demote
            self.rerecord = rerecord
            self.restore = restore
            self.forget = forget
        }

        public var isEmpty: Bool { demote.isEmpty && rerecord.isEmpty && restore.isEmpty && forget.isEmpty }
    }

    public static func plan(_ input: Input) -> Plan {
        let table = ProcessTable(input.processes)
        // A table without BatFi in it is a failed or partial read, not a Mac on which
        // everything BatFi demoted has exited. Forgetting the ledger on it would lose the
        // only record of what to give back.
        guard table.byPID[input.ownPID] != nil else { return Plan() }

        let desired = input.isActive ? desiredDemotions(input, table) : [:]

        var recorded: [ProcessIdentity: ThrottleLedgerEntry] = [:]
        for entry in input.ledger where recorded[entry.identity] == nil {
            recorded[entry.identity] = entry
        }
        var demote: [ProcessIdentity: ThrottleLedgerEntry] = [:]
        var rerecord: [ProcessIdentity: ThrottleLedgerEntry] = [:]
        for (identity, entry) in desired {
            switch recorded[identity] {
            case nil: demote[identity] = entry
            case let existing? where existing != entry: rerecord[identity] = entry
            default: break
            }
        }

        let (restore, forget) = release(
            ledger: input.ledger,
            keeping: desired,
            in: table,
            mayRestore: { process in
                process.pid > 1
                    && process.uid == input.currentUID
                    && process.pid != input.ownPID
                    && !input.unmanageable.contains(process.identity)
            }
        )
        return Plan(demote: demote, rerecord: rerecord, restore: restore, forget: forget)
    }

    /// What to give back when BatFi starts: everything the ledger says an earlier run left
    /// demoted — after a crash, say — together with whatever inherited it. The same
    /// release a pass with nothing to slow makes, including its failed-read guard.
    public static func reconcileAtLaunch(
        ledger: [ThrottleLedgerEntry],
        processes: [ProcessRecord],
        currentUID: UInt32,
        ownPID: Int32
    ) -> (restore: Set<ProcessIdentity>, forget: Set<ProcessIdentity>) {
        let reconciled = plan(Input(
            isActive: false,
            slowedApps: [:],
            runningApps: [],
            processes: processes,
            frontmostPID: nil,
            frontmostBundleID: nil,
            recentlyActiveBundleIDs: [],
            audioActivePIDs: [],
            quittingBundleIDs: [],
            currentUID: currentUID,
            ownPID: ownPID,
            ledger: ledger,
            unmanageable: []
        ))
        return (reconciled.restore, reconciled.forget)
    }

    // MARK: - Demotion

    private static func desiredDemotions(_ input: Input, _ table: ProcessTable) -> [ProcessIdentity: ThrottleLedgerEntry] {
        let ownCoalition = table.byPID[input.ownPID]?.coalitionID

        func mayDemote(_ process: ProcessRecord) -> Bool {
            process.pid > 1
                && process.uid == input.currentUID
                && process.pid != input.ownPID
                && (ownCoalition == nil || process.coalitionID != ownCoalition)
                && !input.unmanageable.contains(process.identity)
        }

        let quittingPIDs = quittingPIDs(input)

        var desired: [ProcessIdentity: ThrottleLedgerEntry] = [:]
        // Sorted so that a process two slowed apps both reach is attributed the same way on
        // every pass.
        let slowedInstances = input.runningApps
            .filter { isSlowed($0, input) }
            .sorted { ($0.bundleID, $0.pid) < ($1.bundleID, $1.pid) }

        for app in slowedInstances {
            guard let mode = input.slowedApps[app.bundleID],
                  let reach = reach(of: app, input: input, table: table),
                  sparing(app, mode: mode, reach: reach, input: input, quittingPIDs: quittingPIDs).isEmpty
            else { continue }

            for process in reach.targets where mayDemote(process) && desired[process.identity] == nil {
                desired[process.identity] = ThrottleLedgerEntry(
                    identity: process.identity,
                    bundleID: app.bundleID,
                    coalitionID: process.coalitionID
                )
            }
        }
        return desired
    }

    /// Whether the instance is one of an app the user slows that BatFi may slow.
    static func isSlowed(_ app: RunningAppRecord, _ input: Input) -> Bool {
        app.isEligible && input.slowedApps[app.bundleID] != nil
    }

    /// Every running instance of an app asked to quit, whatever its policy: the quit goes to
    /// all of them.
    static func quittingPIDs(_ input: Input) -> Set<Int32> {
        Set(input.runningApps.filter { input.quittingBundleIDs.contains($0.bundleID) }.map(\.pid))
    }

    /// What an instance of a slowed app reaches.
    struct Reach {
        /// What the exemptions look at: its coalition, or its process tree where the
        /// coalition cannot be read.
        let neighbourhood: [ProcessRecord]
        /// What gets demoted: the neighbourhood, narrowed to the app's process tree where the
        /// coalition also runs another regular app that is not slowed.
        let targets: [ProcessRecord]
    }

    /// Nil where the instance has no process in the table to start from.
    static func reach(of app: RunningAppRecord, input: Input, table: ProcessTable) -> Reach? {
        guard app.pid > 1, let appProcess = table.byPID[app.pid] else { return nil }

        /// Whether the coalition also runs another regular app that is not slowed.
        func isShared(_ coalition: UInt64) -> Bool {
            input.runningApps.contains { other in
                other.isRegular
                    && other.bundleID != app.bundleID
                    && !isSlowed(other, input)
                    && table.byPID[other.pid]?.coalitionID == coalition
            }
        }

        if let coalition = appProcess.coalitionID {
            let neighbourhood = table.members(of: coalition)
            return Reach(
                neighbourhood: neighbourhood,
                targets: isShared(coalition) ? table.subtrees(of: [app.pid]) : neighbourhood
            )
        }
        let tree = table.subtrees(of: [app.pid])
        return Reach(neighbourhood: tree, targets: tree)
    }

    /// Why an instance of a slowed app is left alone.
    enum Sparing: Hashable {
        /// Its neighbourhood holds BatFi.
        case batFi
        /// Something in its neighbourhood plays or records audio.
        case audio
        /// It, or something in its neighbourhood, has just been asked to quit.
        case quitting
        /// In `backgroundOnly` mode: it or its neighbourhood is in front, or it left the
        /// front a moment ago.
        case inUse
    }

    /// Every reason that leaves the instance alone; empty where none does and it is slowed.
    static func sparing(
        _ app: RunningAppRecord,
        mode: SlowDownMode,
        reach: Reach,
        input: Input,
        quittingPIDs: Set<Int32>
    ) -> Set<Sparing> {
        let neighbourhoodPIDs = Set(reach.neighbourhood.map(\.pid))
        var reasons = Set<Sparing>()
        if neighbourhoodPIDs.contains(input.ownPID) { reasons.insert(.batFi) }
        if !neighbourhoodPIDs.isDisjoint(with: input.audioActivePIDs) { reasons.insert(.audio) }
        // An app's own pid is always in its neighbourhood, so this spares the app asked to
        // quit, and any other slowed app whose claim would reach its processes.
        if !neighbourhoodPIDs.isDisjoint(with: quittingPIDs) { reasons.insert(.quitting) }
        if mode == .backgroundOnly {
            if input.frontmostBundleID == app.bundleID
                || input.frontmostPID.map(neighbourhoodPIDs.contains) == true
                || input.recentlyActiveBundleIDs.contains(app.bundleID)
            {
                reasons.insert(.inUse)
            }
        }
        return reasons
    }

    // MARK: - Giving back

    /// Everything to give back and forget, given what stays demoted.
    ///
    /// Each coalition and each process is visited at most once, however many entries lead
    /// to it.
    ///
    /// - Parameter mayRestore: which processes that are not in the ledger may be restored for
    ///   having inherited a demotion. Ledger entries themselves are always given back.
    private static func release(
        ledger: [ThrottleLedgerEntry],
        keeping desired: [ProcessIdentity: ThrottleLedgerEntry],
        in table: ProcessTable,
        mayRestore: (ProcessRecord) -> Bool
    ) -> (restore: Set<ProcessIdentity>, forget: Set<ProcessIdentity>) {
        var restore = Set<ProcessIdentity>()
        var forget = Set<ProcessIdentity>()
        var coalitions = Set<UInt64>()
        var roots: [Int32] = []
        // launchd starts with the boot. Coalition IDs start over at every boot, so an entry
        // older than launchd names a coalition that is somebody else's by now.
        let boot = table.byPID[1]?.identity

        for entry in ledger {
            if let process = table.alive(entry.identity) {
                guard desired[entry.identity] == nil else { continue }
                restore.insert(entry.identity)
                if let coalition = entry.coalitionID { coalitions.insert(coalition) }
                // Where the coalition could not be read at the time, it may be readable now.
                if let coalition = process.coalitionID { coalitions.insert(coalition) }
                roots.append(entry.identity.pid)
            } else {
                forget.insert(entry.identity)
                // What it spawned after its demotion is still in its coalition; its
                // descendants were reparented to launchd, so there is no tree to walk.
                if let coalition = entry.coalitionID, boot.map({ !entry.identity.started(before: $0) }) ?? true {
                    coalitions.insert(coalition)
                }
            }
        }

        let inheritors = coalitions.flatMap { table.members(of: $0) } + table.subtrees(of: roots)
        for process in inheritors where desired[process.identity] == nil && mayRestore(process) {
            restore.insert(process.identity)
        }
        return (restore, forget)
    }
}

/// The process table, indexed the ways the policy walks it.
struct ProcessTable {
    let byPID: [Int32: ProcessRecord]
    private let childrenByPID: [Int32: [ProcessRecord]]
    private let membersByCoalition: [UInt64: [ProcessRecord]]

    init(_ processes: [ProcessRecord]) {
        byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let unique = Array(byPID.values)
        childrenByPID = Dictionary(grouping: unique, by: \.ppid)
        var members: [UInt64: [ProcessRecord]] = [:]
        for process in unique {
            if let coalition = process.coalitionID { members[coalition, default: []].append(process) }
        }
        membersByCoalition = members
    }

    /// The process with this identity, if it is still running — the same pid with a
    /// different start time is another process.
    func alive(_ identity: ProcessIdentity) -> ProcessRecord? {
        guard let process = byPID[identity.pid], process.identity == identity else { return nil }
        return process
    }

    func members(of coalition: UInt64) -> [ProcessRecord] {
        membersByCoalition[coalition] ?? []
    }

    /// The processes and everything below them in the process tree, each once. Never walked
    /// from launchd or the kernel, whose descendants are everything.
    func subtrees(of roots: [Int32]) -> [ProcessRecord] {
        var found: [ProcessRecord] = []
        var visited = Set<Int32>()
        for pid in roots where pid > 1 {
            guard let root = byPID[pid], visited.insert(pid).inserted else { continue }
            var index = found.count
            found.append(root)
            while index < found.count {
                for child in childrenByPID[found[index].pid] ?? [] where visited.insert(child.pid).inserted {
                    found.append(child)
                }
                index += 1
            }
        }
        return found
    }
}
