//
//  HelperShutdownPolicy.swift
//  BatFi
//
//  Decides when the helper stops being the helper. Pure: no XPC, no dispatch sources, no
//  clock of its own, so the rule that matters — a root daemon outlives nobody, and tears
//  nothing down early — is provable in a unit test rather than owed as a hardware check.
//
//  The helper used to learn that the app was gone in exactly one way: by being told, over
//  XPC. That makes its lifetime depend on the app being alive, cooperative, and quick enough
//  to send the message, none of which hold in the case that matters most. When the message
//  is missed the process survives, and launchd keeps the mach service bound to *it* rather
//  than to the binary on disk — so after an in-place update the relaunched app is routed to
//  the old build, out of a bundle that has already been replaced underneath it.
//
//  What replaces it is the client's *process*, watched directly. That signal survives every
//  way an app can die — crash, jetsam, force-quit, an installer's `SIGKILL` — and needs no
//  cooperation from it.
//
//  The asymmetry below is deliberate and is the whole design:
//
//  * A **connection** dying proves nothing. `XPCClient` tears connections down on purpose
//    when a call goes unanswered and builds a new one on the next call.
//  * A **process** dying is proof.
//
//  Both directions have a consequence that reaches hardware. Acting too late strands a
//  helper the next launch cannot use. Acting too early releases a firmware charge band the
//  live app is still asking for — enforced by the firmware, invisible in System Settings,
//  and outliving every process that knows about it.
//

import Foundation

public struct HelperShutdownPolicy: Sendable {
    /// Identifies one XPC connection. The helper mints these; nothing outside compares them
    /// to anything but each other.
    public typealias ConnectionID = UUID

    public enum Reason: Sendable, Equatable {
        /// Every client process the helper was serving has exited.
        case lastClientDied
        /// A client asked over XPC. Either our own app quitting in an orderly way, or
        /// another copy evicting this helper to take the daemon over.
        case askedToQuit
        /// Spawned by launchd for a lookup that never became a connection.
        case neverUsed
    }

    public enum Decision: Sendable, Equatable {
        /// Arm a process-exit watch on this pid. Emitted once per pid, never once per
        /// connection: an app that reconnects after a watchdog teardown would otherwise leak
        /// a dispatch source per teardown for the life of the daemon.
        case watchProcess(pid_t)
        case stopWatching(pid_t)
        /// Hand the hardware back, then exit. The restore has to finish first and has to be
        /// bounded — see the caller.
        case restoreThenExit(Reason)
        /// Exit holding nothing. Reachable only from the startup grace, where by
        /// construction the helper never had a client and so never drove anything.
        case exitWithoutRestoring(Reason)
    }

    public enum Event: Sendable, Equatable {
        case clientConnected(ConnectionID, pid: pid_t)
        case connectionInvalidated(ConnectionID)
        case clientProcessExited(pid_t)
        case quitRequested
        case startupGraceExpired
    }

    /// Live connections per client process.
    ///
    /// Keyed by pid rather than counted in aggregate, because the count cannot answer the
    /// question that decides everything here: *whose* connection was that. Two copies of
    /// BatFi can be connected at once, and the helper belongs to neither until both are
    /// gone.
    ///
    /// A pid stays in this table with an empty set once its connections drop. That is not an
    /// oversight — it is what makes a teardown a no-op and stops the reconnection that
    /// follows from arming a second watch.
    private var connectionsByClient: [pid_t: Set<ConnectionID>] = [:]

    /// Whether anything ever connected. Distinct from "anything is connected now": a client
    /// that connected and then dropped its connection is still a client whose death the
    /// helper is waiting for, and the startup grace must not race that.
    private var hasEverHadAClient = false

    public init() {}

    public mutating func handle(_ event: Event) -> [Decision] {
        switch event {
        case let .clientConnected(connection, pid):
            hasEverHadAClient = true
            let isFirstForThisProcess = connectionsByClient[pid] == nil
            connectionsByClient[pid, default: []].insert(connection)
            return isFirstForThisProcess ? [.watchProcess(pid)] : []

        case let .connectionInvalidated(connection):
            // Deliberately inert. The process watch is the only thing that decides anything,
            // and it is still armed.
            guard let pid = connectionsByClient.first(where: { $0.value.contains(connection) })?.key else {
                return []
            }
            connectionsByClient[pid]?.remove(connection)
            return []

        case let .clientProcessExited(pid):
            // A pid already dropped is one whose exit was already acted on. Reachable
            // because the caller synthesizes this event when it finds a pid already dead at
            // arming time, which can coincide with the real watch firing.
            guard connectionsByClient.removeValue(forKey: pid) != nil else { return [] }
            var decisions: [Decision] = [.stopWatching(pid)]
            if connectionsByClient.isEmpty {
                decisions.append(.restoreThenExit(.lastClientDied))
            }
            return decisions

        case .quitRequested:
            // Restores even though our own app restores before it sends this. The other
            // caller is `HelperConnectionManager.takeOwnership()`, evicting a *foreign*
            // helper that may be holding a firmware charge band, and nothing else in that
            // sequence can release it.
            return [.restoreThenExit(.askedToQuit)]

        case .startupGraceExpired:
            guard !hasEverHadAClient else { return [] }
            return [.exitWithoutRestoring(.neverUsed)]
        }
    }
}
