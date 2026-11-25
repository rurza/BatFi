//
//  SettledSignals.swift
//  BatFi
//
//  Answers a stream of "look again" signals once per burst, and lets the stream end when
//  the task running it is cancelled — wherever the task happens to be.
//

import Foundation

public enum SettledSignals {
    /// Runs `body` once for each signal, after letting it settle, until the stream ends or
    /// the task is cancelled.
    ///
    /// Signals that arrive while settling, or while `body` runs, fold into the one the stream
    /// buffers — the live signal streams keep only the newest — so a burst costs one follow-up
    /// run, not one each.
    ///
    /// **Cancellation always ends the stream.** A stream ends — and runs its termination
    /// handler, which is what removes the listeners behind it — only when it is asked for its
    /// next element from a cancelled task, or is deallocated. The live streams are never
    /// deallocated early: their continuation is held by the listener their termination
    /// handler removes. So every way out of this loop goes back to the stream: cancelled while
    /// settling, the body is skipped and the loop asks for the next signal, which the
    /// cancellation turns into the end. `AsyncAlgorithms`' `debounce` does not: cancelled
    /// while its consumer is busy, it never cancels the stream it reads, and the listeners
    /// stay for the rest of the session.
    public static func forEach(
        _ signals: AsyncStream<Void>,
        settlingFor settle: Duration,
        on clock: any Clock<Duration>,
        _ body: @Sendable () async -> Void
    ) async {
        for await _ in signals {
            // Not `return`: leaving here would drop the stream without ending it.
            guard (try? await clock.sleep(for: settle)) != nil, !Task.isCancelled else { continue }
            await body()
        }
    }
}
