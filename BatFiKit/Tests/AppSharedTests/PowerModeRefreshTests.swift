//
//  PowerModeRefreshTests.swift
//  BatFi
//
//  Unit tests for the loop that reads the power mode for the battery icon. The case that
//  matters most is a failed read: it once ended the loop for good, leaving the icon's
//  mode frozen until relaunch.
//

import Foundation
import Testing

@testable import AppShared

@Suite struct PowerModeRefreshTests {
    private struct ReadFailed: Error {}

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [Int] = []
        private var _errors = 0
        private var _reads = 0

        var values: [Int] { lock.withLock { _values } }
        var errors: Int { lock.withLock { _errors } }

        func nextRead() -> Int { lock.withLock { _reads += 1; return _reads } }
        func record(_ value: Int) { lock.withLock { _values.append(value) } }
        func recordError() { lock.withLock { _errors += 1 } }
    }

    @Test func keepsReadingAfterAFailedRead() async {
        let recorder = Recorder()
        let (requests, continuation) = AsyncStream<Void>.makeStream()
        for _ in 0..<3 { continuation.yield() }
        continuation.finish()

        await PowerModeRefresh.run(
            requests: requests,
            read: {
                let read = recorder.nextRead()
                if read == 2 { throw ReadFailed() }
                return read
            },
            onValue: { recorder.record($0) },
            onError: { _ in recorder.recordError() }
        )

        #expect(recorder.values == [1, 3])
        #expect(recorder.errors == 1)
    }

    @Test func endsWhenItsTaskIsCancelled() async {
        let recorder = Recorder()
        let (requests, continuation) = AsyncStream<Void>.makeStream()

        let task = Task {
            await PowerModeRefresh.run(
                requests: requests,
                read: { recorder.nextRead() },
                onValue: { recorder.record($0) },
                onError: { _ in recorder.recordError() }
            )
        }
        continuation.yield()
        task.cancel()
        // The stream is never finished, so returning at all shows cancellation ends it.
        await task.value

        #expect(recorder.errors == 0)
    }
}
