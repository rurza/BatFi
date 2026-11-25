//
//  ProcessTableScanner.swift
//  BatFi
//
//  Puts together the process table the throttle policy reads from the kernel's answers,
//  asking for each process's resource coalition once.
//

import Foundation

/// Builds `BackgroundThrottlePolicy`'s process table, and remembers each process's resource
/// coalition so that it is read once per process rather than on every scan.
///
/// A process never changes coalition while it runs, so once read, a coalition is kept for as
/// long as the process does. One that could not be read is not remembered: it is asked for
/// again on the next scan. Processes that have exited are forgotten at every scan.
///
/// The kernel calls themselves are handed in, so that what is asked for, and when, can be
/// checked without them.
public struct ProcessTableScanner: Sendable {
    /// One process as the kernel lists it, before its coalition is known.
    public struct Row: Hashable, Sendable {
        public let identity: ProcessIdentity
        public let ppid: Int32
        public let uid: UInt32

        public init(identity: ProcessIdentity, ppid: Int32, uid: UInt32) {
            self.identity = identity
            self.ppid = ppid
            self.uid = uid
        }
    }

    /// The coalitions read so far, of the processes running at the last scan.
    private(set) var knownCoalitions: [ProcessIdentity: UInt64] = [:]

    public init() {}

    /// The whole process table, or none.
    ///
    /// - Parameters:
    ///   - pids: the processes the kernel listed, or nil where the listing failed.
    ///   - ownPID: BatFi's pid. A table without BatFi in it is not whole: the policy takes it
    ///     for a failed read, so it is not handed over.
    ///   - row: reads one process, or answers nil where it has exited since it was listed.
    ///   - coalition: reads a process's resource coalition, or answers nil where it could
    ///     not be read.
    /// - Returns: every process that is still running, or nothing where the table is not
    ///   whole. Never part of one.
    public mutating func scan(
        pids: [Int32]?,
        ownPID: Int32,
        row: (Int32) -> Row?,
        coalition: (Int32) -> UInt64?
    ) -> [ProcessRecord] {
        guard let pids else { return [] }

        var table: [ProcessRecord] = []
        var listed = Set<Int32>()
        var found = knownCoalitions
        for pid in pids where pid > 0 && listed.insert(pid).inserted {
            // Gone since it was listed; the rest of the table stands.
            guard let process = row(pid) else { continue }
            let coalitionID = found[process.identity] ?? coalition(pid)
            if let coalitionID { found[process.identity] = coalitionID }
            table.append(ProcessRecord(
                identity: process.identity,
                ppid: process.ppid,
                uid: process.uid,
                coalitionID: coalitionID
            ))
        }

        // A table that is not whole says nothing about which processes exited, so nothing
        // is forgotten on it.
        guard table.contains(where: { $0.identity.pid == ownPID }) else {
            knownCoalitions = found
            return []
        }

        let running = Set(table.map(\.identity))
        knownCoalitions = found.filter { running.contains($0.key) }
        return table
    }
}
