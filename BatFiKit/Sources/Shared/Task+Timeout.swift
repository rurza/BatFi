//
//  Task+Timeout.swift
//
//
//  Created by Adam Różyński on 27/03/2024.
//

import Foundation

public enum TaskError: Error {
    case timedOut
}

public func withTimeout<R>(
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
