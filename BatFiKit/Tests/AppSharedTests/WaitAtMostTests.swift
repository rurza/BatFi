//
//  WaitAtMostTests.swift
//  BatFi
//
//  Unit tests for the wait that returns when its budget runs out, whether or not the work
//  it was waiting on can be cancelled.
//

import Foundation
import Testing

@testable import Shared

// Serialized with the deadlock stress test; see `CPUSaturationSensitiveTests`.
extension CPUSaturationSensitiveTests {
    @Suite struct WaitAtMostTests {
        /// Work that cancellation cannot reach, shaped like `Subprocess` waiting on a child: a
        /// continuation resumed from a dispatch queue.
        private static func uncancellableWork(lasting seconds: Double) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    continuation.resume()
                }
            }
        }

        @Test func answersTrueWhenTheWorkFinishesInTime() async {
            let finished = await waitAtMost(.seconds(10)) {
                await Self.uncancellableWork(lasting: 0.01)
            }
            #expect(finished)
        }

        @Test func returnsAtTheBudgetWhenTheWorkIgnoresCancellation() async {
            let clock = ContinuousClock()
            let start = clock.now
            let finished = await waitAtMost(.milliseconds(200)) {
                await Self.uncancellableWork(lasting: 5)
            }
            let elapsed = clock.now - start
            #expect(!finished)
            // Generous against a loaded test runner; the work itself takes 5s.
            #expect(elapsed < .seconds(2))
        }

        @Test func theWorkIsLeftRunningRatherThanAbandonedHalfway() async {
            let done = DoneFlag()
            let finished = await waitAtMost(.milliseconds(50)) {
                await Self.uncancellableWork(lasting: 0.3)
                done.set()
            }
            #expect(!finished)
            await Self.uncancellableWork(lasting: 1)
            #expect(done.isSet)
        }
    }
}

private final class DoneFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
