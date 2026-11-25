//
//  ManualClock.swift
//  BatFi
//
//  A clock for tests whose time moves only when the test moves it.
//

import Foundation

/// A `Clock` that stands still until `advance(by:)`. Its sleepers wake once time reaches
/// their deadline, and throw `CancellationError` when their task is cancelled first, as a
/// real clock's do.
final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol, Hashable {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: UUID
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    /// How many tasks are asleep on this clock right now.
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enum Outcome { case wait, wake, cancel }
                // Checked under the lock the cancellation handler takes too: a task cancelled
                // before it got here has its flag set already, and one cancelled after finds
                // its sleeper to remove.
                let outcome: Outcome = lock.withLock {
                    if Task.isCancelled { return .cancel }
                    if deadline <= current { return .wake }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .wait
                }
                switch outcome {
                case .wait: break
                case .wake: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let sleeper: Sleeper? = lock.withLock {
                guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return sleepers.remove(at: index)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time on, waking every sleeper whose deadline it reaches.
    func advance(by duration: Duration) {
        let due: [Sleeper] = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
    }
}

/// Waits, in real time and for at most two seconds, until `condition` holds.
func eventually(_ condition: @Sendable () -> Bool) async -> Bool {
    for _ in 0 ..< 2000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return condition()
}

/// A flag set from any thread and read from the test.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// A counter bumped from any thread and read from the test.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

/// A gate a task waits at, deaf to cancellation, until the test opens it.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passes: Bool = lock.withLock {
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
    }

    func open() {
        let waiting: [CheckedContinuation<Void, Never>] = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}
