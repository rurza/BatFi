//
//  PowerModeRefresh.swift
//  BatFi
//
//  The loop behind the battery icon's power mode: one read of the helper per request.
//

import Foundation

public enum PowerModeRefresh {
    /// Reads once for every element `requests` delivers, one read at a time, until the
    /// stream finishes or the calling task is cancelled.
    ///
    /// A read that throws is reported and skipped, and the loop waits for the next
    /// request. It used to end the loop instead: the helper being briefly unreachable
    /// once was enough to leave the icon's mode stuck until BatFi was relaunched, with
    /// nothing in the log to say so.
    ///
    /// Reads never overlap, because the next request is only taken once the read in
    /// flight has finished. A `requests` stream that buffers only its newest element
    /// therefore folds a burst of requests made during a read into a single read after it.
    public static func run<Value: Sendable>(
        requests: AsyncStream<Void>,
        read: @Sendable () async throws -> Value,
        onValue: @Sendable (Value) -> Void,
        onError: @Sendable (any Error) -> Void
    ) async {
        for await _ in requests {
            if Task.isCancelled { return }
            do {
                onValue(try await read())
            } catch {
                // A read cut short because the loop itself is being torn down is not a
                // failure worth reporting.
                if Task.isCancelled { return }
                onError(error)
            }
        }
    }
}
