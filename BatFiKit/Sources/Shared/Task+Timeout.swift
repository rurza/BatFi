//
//  Task+Timeout.swift
//
//
//  Created by Adam Różyński on 27/03/2024.
//

import Foundation
import os

public enum TaskError: Error {
    case timedOut
}

public func withTimeout<R: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> R
) async throws -> R {
    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = Date(timeIntervalSinceNow: seconds)

        // Start actual work.
        group.addTask {
            let result = try await operation()
            try Task.checkCancellation()
            return result
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            try Task.checkCancellation()
            // We’ve reached the timeout.
            throw TaskError.timedOut
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// Waits for `operation` for at most `budget`, and answers whether it finished in that time.
///
/// Unlike `withTimeout`, this returns on time even when the work cannot be cancelled.
/// `withTimeout` runs its work as a child of a task group, and a group does not return until
/// every child has — so where the work is blocked in something cancellation cannot reach
/// (`Subprocess` waiting on a child process, say), its timeout lasts exactly as long as the
/// work does. Here the work runs in a task of its own and is left running when the budget is
/// spent: it is cancelled, and finishes when it finishes or when the process exits.
///
/// The deadline is a dispatch timer rather than a task sleep, so it fires even when the
/// cooperative pool has no thread free.
@discardableResult
public func waitAtMost(
    _ budget: Duration,
    for operation: @escaping @Sendable () async -> Void
) async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let hasAnswered = OSAllocatedUnfairLock(initialState: false)
        @Sendable func answer(_ finished: Bool) {
            let isFirst = hasAnswered.withLock { answered in
                defer { answered = true }
                return !answered
            }
            if isFirst { continuation.resume(returning: finished) }
        }

        let work = Task {
            await operation()
            answer(true)
        }
        let (seconds, attoseconds) = budget.components
        let interval = max(0, Double(seconds) + Double(attoseconds) / 1e18)
        DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
            work.cancel()
            answer(false)
        }
    }
}
