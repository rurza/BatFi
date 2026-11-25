//
//  SettledSignalsTests.swift
//  BatFi
//
//  Unit tests for the loop that answers a stream of "look again" signals once per burst,
//  and — the reason it exists — always lets the stream end when its task is cancelled, so
//  whatever the stream holds open is released.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct SettledSignalsTests {
    private let settle: Duration = .milliseconds(300)

    /// A signal stream as the live client makes them: newest-only, with a termination handler
    /// standing in for the CoreAudio listeners it would remove.
    private func signals() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation, Flag) {
        let terminated = Flag()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { _ in terminated.set() }
        return (stream, continuation, terminated)
    }

    @Test func theBodyRunsOnlyOnceTheSignalHasSettled() async {
        let (stream, continuation, _) = signals()
        let clock = ManualClock()
        let runs = Counter()
        let loop = Task {
            await SettledSignals.forEach(stream, settlingFor: settle, on: clock) { runs.increment() }
        }
        defer { loop.cancel() }

        continuation.yield()
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(299))
        #expect(clock.sleeperCount == 1)
        #expect(runs.count == 0)

        clock.advance(by: .milliseconds(1))
        #expect(await eventually { runs.count == 1 })
    }

    @Test func aBurstDuringTheSettleFoldsIntoOneFollowUp() async {
        let (stream, continuation, _) = signals()
        let clock = ManualClock()
        let runs = Counter()
        let loop = Task {
            await SettledSignals.forEach(stream, settlingFor: settle, on: clock) { runs.increment() }
        }
        defer { loop.cancel() }

        continuation.yield()
        #expect(await eventually { clock.sleeperCount == 1 })
        for _ in 0 ..< 5 { continuation.yield() }
        clock.advance(by: settle)
        #expect(await eventually { runs.count == 1 })

        // The five folded into one: one more settle, one more run, then nothing.
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: settle)
        #expect(await eventually { runs.count == 2 })
        try? await Task.sleep(for: .milliseconds(20))
        #expect(clock.sleeperCount == 0)
        #expect(runs.count == 2)
    }

    /// A signal stream that never signals, and shows when its consumer is waiting in `next()`
    /// — which a stream made with a continuation cannot. Like the live streams, it ends,
    /// running its termination handler, when the consumer is cancelled while it waits.
    private func silentSignals() -> (AsyncStream<Void>, Waiters, Flag) {
        let waiters = Waiters()
        let terminated = Flag()
        let stream = AsyncStream<Void>(
            unfolding: {
                await waiters.wait()
                return nil
            },
            onCancel: { terminated.set() }
        )
        return (stream, waiters, terminated)
    }

    @Test func cancellingWhileWaitingForASignalEndsTheStream() async {
        let (stream, waiters, terminated) = silentSignals()
        let clock = ManualClock()
        let loop = Task {
            await SettledSignals.forEach(stream, settlingFor: settle, on: clock) {}
        }
        // Waiting for a signal, and not settling one.
        #expect(await eventually { waiters.count == 1 })
        #expect(clock.sleeperCount == 0)

        loop.cancel()

        #expect(await eventually { terminated.isSet })
        await loop.value
        #expect(waiters.count == 0)
    }

    @Test func cancellingWhileSettlingEndsTheStreamWithoutRunningTheBody() async {
        let (stream, continuation, terminated) = signals()
        let clock = ManualClock()
        let runs = Counter()
        let loop = Task {
            await SettledSignals.forEach(stream, settlingFor: settle, on: clock) { runs.increment() }
        }
        continuation.yield()
        #expect(await eventually { clock.sleeperCount == 1 })

        loop.cancel()

        #expect(await eventually { terminated.isSet })
        await loop.value
        #expect(runs.count == 0)
    }

    /// The case `debounce` gets wrong: cancelled while the body runs, it never cancels its
    /// upstream, and the stream's termination — the listeners' removal — never happens.
    @Test func cancellingWhileTheBodyRunsEndsTheStreamOnceTheBodyReturns() async {
        let (stream, continuation, terminated) = signals()
        let clock = ManualClock()
        let entered = Flag()
        let gate = Gate()
        let loop = Task {
            await SettledSignals.forEach(stream, settlingFor: settle, on: clock) {
                entered.set()
                await gate.wait()
            }
        }
        continuation.yield()
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: settle)
        #expect(await eventually { entered.isSet })

        loop.cancel()
        // A signal arriving meanwhile must not keep it going either.
        continuation.yield()
        gate.open()

        #expect(await eventually { terminated.isSet })
        await loop.value
    }
}

/// A place tasks wait until they are cancelled, which counts who is waiting there: a task
/// counted is suspended, its continuation stored.
private final class Waiters: @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: [UUID: CheckedContinuation<Void, Never>] = [:]

    var count: Int { lock.withLock { waiting.count } }

    func wait() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                // Checked under the lock the cancellation handler takes too, as `ManualClock`
                // does: cancelled before this, the flag is set; after, the handler finds it.
                let cancelled: Bool = lock.withLock {
                    if Task.isCancelled { return true }
                    waiting[id] = continuation
                    return false
                }
                if cancelled { continuation.resume() }
            }
        } onCancel: {
            let continuation = lock.withLock { waiting.removeValue(forKey: id) }
            continuation?.resume()
        }
    }
}
