//
//  AudioActivityReading.swift
//  BatFi
//
//  Which processes are playing or recording audio — and when that cannot be told, saying
//  so rather than answering "nobody".
//

import Foundation

/// Decides, from CoreAudio's answers, which processes are playing or recording audio.
///
/// A demoted process loses its real-time threads, so a process wrongly taken for silent
/// would be slowed while it plays, and its sound would break up. Where the answer is not
/// known, it is reported as unknown — nil — never as an empty set; the caller keeps what it
/// knew before.
public enum AudioActivityReading {
    /// What one of CoreAudio's process objects says.
    public enum ProcessState: Equatable, Sendable {
        /// Running audio input or output.
        case active(pid: Int32)
        case idle
        /// Its process left the audio system after the list was read.
        case gone
        /// Still there, but could not say whether it is running input or output — with its
        /// pid, or nil where not even that could be read.
        case unreadable(pid: Int32?)
    }

    /// How many times a list is measured and read before it is given up on.
    public static let attempts = 3
    /// Room left for processes that connect between measuring the list and reading it.
    public static let slack = 8

    /// Reads a list that may grow between being measured and being read.
    ///
    /// A read that fills all the room it was given may have been cut short, so the list is
    /// measured and read again, as is one whose measurement or read failed.
    ///
    /// - Parameters:
    ///   - count: how many entries the list has now, or nil where that could not be asked.
    ///   - read: reads at most `capacity` entries, or answers nil where the read failed.
    /// - Returns: the whole list, or nil where it could not be read whole in `attempts`.
    public static func readList<Element>(
        count: () -> Int?,
        read: (_ capacity: Int) -> [Element]?
    ) -> [Element]? {
        for _ in 0 ..< attempts {
            guard let count = count(), count >= 0 else { continue }
            let capacity = count + slack
            guard let list = read(capacity), list.count < capacity else { continue }
            return list
        }
        return nil
    }

    /// The processes playing or recording audio, or nil where that is not known: the list
    /// could not be read, or a process on it could not even say which process it is.
    ///
    /// A process that says who it is but not whether it plays is taken for playing. That
    /// errs on the safe side — only its app is spared — and it keeps one such process from
    /// leaving the whole answer unknown for as long as it runs.
    public static func activePIDs(
        of processes: [UInt32]?,
        state: (UInt32) -> ProcessState
    ) -> Set<Int32>? {
        activity(of: processes, state: state)?.activePIDs
    }

    /// What one reading found: who is taken for playing, and who only on a guess.
    public struct Activity: Equatable, Sendable {
        /// The processes taken for playing or recording audio. See `activePIDs(of:state:)`.
        public var activePIDs: Set<Int32>
        /// Those among them that could not say whether they play, and none of whose objects
        /// said they do. Their apps are left unslowed on a guess, which is worth a line in
        /// the log: nothing else would explain an app that is never slowed.
        public var unreadablePIDs: Set<Int32>

        public init(activePIDs: Set<Int32>, unreadablePIDs: Set<Int32>) {
            self.activePIDs = activePIDs
            self.unreadablePIDs = unreadablePIDs
        }
    }

    /// `activePIDs(of:state:)`, telling apart the processes taken for playing on a guess.
    public static func activity(
        of processes: [UInt32]?,
        state: (UInt32) -> ProcessState
    ) -> Activity? {
        guard let processes else { return nil }
        var playing = Set<Int32>()
        var unreadable = Set<Int32>()
        for process in processes {
            switch state(process) {
            case let .active(pid) where pid > 0:
                playing.insert(pid)
            case let .unreadable(pid?) where pid > 0:
                unreadable.insert(pid)
            case .active, .unreadable(.some), .idle, .gone:
                continue
            case .unreadable(nil):
                return nil
            }
        }
        return Activity(activePIDs: playing.union(unreadable), unreadablePIDs: unreadable.subtracting(playing))
    }
}

/// Remembers which keys have been reported, so that each is reported once however often it
/// comes up, and from whichever thread.
public final class ReportedOnce<Key: Hashable & Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var reported: Set<Key> = []

    public init() {}

    /// The keys not reported before, which count as reported from now on.
    public func firstReports(of keys: Set<Key>) -> Set<Key> {
        lock.withLock {
            let first = keys.subtracting(reported)
            reported.formUnion(first)
            return first
        }
    }
}
