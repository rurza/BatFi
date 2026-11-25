//
//  CombineLatestCancellationDeadlockTests.swift
//  BatFi
//
//  Stress reproduction for rurza/BatFi#149: the main thread deadlocking on an
//  `os_unfair_lock` inside a task cancellation handler.
//
//  Mechanism (swift-async-algorithms 0.1.0, `CombineLatestStorage`; confirmed by `sample`
//  of a deadlocked run, which matches the customer's stack frame for frame):
//
//  - Cancelling task T takes T's status-record lock and, still holding it, runs T's
//    cancellation handlers. combineLatest's `onCancel` then takes the storage lock and,
//    *inside* it, cancels its upstream task — which walks that task's child tasks under
//    their status-record locks and runs *their* handlers (the nested combineLatest's
//    `onCancel`), which want the nested storage lock.
//  - Meanwhile a producer-side child task holds a storage lock (`elementProduced`) and,
//    still inside it, resumes the downstream continuation of a consumer task. Resuming a
//    suspended task's continuation updates its dependency status record, which takes
//    *that task's* status-record lock.
//
//  Thread A holds [task status lock] and wants [storage lock]; thread B holds
//  [storage lock] and wants [task status lock]. Nesting is not required — a single
//  combineLatest deadlocks the same way (shape 4) — it only adds more locks to the chain.
//
//  Neither lock can be interrupted, so the test can't just time out — a watchdog thread
//  notices a lane that stopped making progress and, if it stays stopped once the
//  producers pause, fails the test (or, if the stuck thread is the main thread, kills the
//  process so the run can't hang forever).
//

import AsyncAlgorithms
import Foundation
import Testing

/// Suites that must not run at the same time as one another.
///
/// The #149 stress test below keeps every core it can busy for five seconds on purpose,
/// and Swift Testing runs suites in parallel. The suites nested here assert wall-clock
/// bounds — a timeout is enforced by SIGTERM rather than the SIGKILL grace, a wait returns
/// at its budget — which measure scheduling latency as much as the code under test, so
/// alongside the stress test they failed on a 6-core CI VM. Serializing them with it keeps
/// the bounds tight instead of loosening them to cover a CPU the test itself saturates.
@Suite(.serialized) enum CPUSaturationSensitiveTests {}

extension CPUSaturationSensitiveTests {
    @Suite(.serialized) struct CombineLatestCancellationDeadlockTests {
        @Test func cancellingNestedCombineLatestDoesNotDeadlock() async {
            let environment = ProcessInfo.processInfo.environment
            let duration = Double(environment["DEADLOCK_STRESS_SECONDS"] ?? "") ?? 5
            let laneCount = Int(environment["DEADLOCK_STRESS_LANES"] ?? "") ?? 12
            // One spinning pump per four cores, at most four: four on a 16-core Mac, one on a
            // 6-core CI VM, where four left the rest of the process two cores to share.
            let defaultPumps = min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 4))
            let pumpThreads = Int(environment["DEADLOCK_STRESS_PUMPS"] ?? "") ?? defaultPumps

            let pump = Pump()
            pump.start(threads: pumpThreads)
            defer { pump.stop() }

            let monitor = Monitor(
                lanes: laneCount,
                stallLimit: 4,
                recoveryGrace: 10,
                pump: pump,
                samplePath: environment["DEADLOCK_SAMPLE_PATH"]
            )
            let deadline = Date().addingTimeInterval(duration)
            let started = Date()

            let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Monitor.Outcome, Never>) in
                monitor.onOutcome(continuation)
                monitor.startWatchdog()
                for lane in 0..<laneCount {
                    Task.detached(priority: lane % 3 == 0 ? .high : .medium) {
                        await runLane(lane, pump: pump, monitor: monitor, deadline: deadline)
                        monitor.laneFinished(lane)
                    }
                }
            }

            let elapsed = Date().timeIntervalSince(started)
            print("[#149 stress] \(monitor.iterationCount) cancellations in \(String(format: "%.1f", elapsed))s across \(laneCount) lanes")
            switch outcome {
            case .finished:
                break
            case let .deadlocked(description):
                Issue.record("Deadlock reproduced after \(String(format: "%.1f", elapsed))s: \(description)")
            }
        }
    }
}

// MARK: - Lanes

private func runLane(_ lane: Int, pump: Pump, monitor: Monitor, deadline: Date) async {
    var iteration = 0
    while Date() < deadline, !monitor.isDeadlocked {
        let shape = (lane + iteration) % 5
        let consumer = makeConsumer(shape: shape, pump: pump)

        // Let the consumer get going and start receiving values, then cancel at a
        // random point while producers are hammering the streams.
        let delay = UInt64.random(in: 0...1_500)
        if delay > 100 {
            try? await Task.sleep(nanoseconds: delay * 1_000)
        } else {
            await Task.yield()
        }

        let onMain = lane % 4 == 0
        monitor.enter(lane, phase: onMain ? "cancel (main actor), shape \(shape)" : "cancel (background), shape \(shape)")
        if onMain {
            await MainActor.run { consumer.cancel() }
        } else {
            consumer.cancel()
        }
        monitor.enter(lane, phase: "await consumer, shape \(shape)")
        _ = await consumer.value
        monitor.completedIteration(lane)
        iteration += 1
    }
}

private func makeConsumer(shape: Int, pump: Pump) -> Task<Int, Never> {
    switch shape {
    case 0:
        // combineLatest(combineLatest(a, b), combineLatest(c, d)) — BatteryInfo / StatusItemManager shape.
        let sequence = combineLatest(
            combineLatest(pump.makeStream(), pump.makeStream()),
            combineLatest(pump.makeStream(), pump.makeStream())
        )
        return Task { await consume(sequence) }
    case 1:
        // combineLatest(combineLatest(a, b), c) — BatteryInfoView+Model mode-description shape.
        let sequence = combineLatest(
            combineLatest(pump.makeStream(), pump.makeStream()),
            pump.makeStream()
        )
        return Task { await consume(sequence) }
    case 2:
        // Nested, with a trailing debounce — ChargingManager shape.
        let sequence = combineLatest(
            combineLatest(pump.makeStream(), pump.makeStream(), pump.makeStream()),
            combineLatest(pump.makeStream(), pump.makeStream())
        )
        .debounce(for: .milliseconds(1))
        return Task { await consume(sequence) }
    case 3:
        // Three levels deep.
        let sequence = combineLatest(
            combineLatest(
                combineLatest(pump.makeStream(), pump.makeStream()),
                pump.makeStream()
            ),
            pump.makeStream()
        )
        return Task { await consume(sequence) }
    default:
        // A single combineLatest — the ABBA needs no nesting in principle.
        let sequence = combineLatest(pump.makeStream(), pump.makeStream())
        return Task { await consume(sequence) }
    }
}

private func consume<S: AsyncSequence & Sendable>(_ sequence: S) async -> Int {
    var count = 0
    do {
        for try await _ in sequence {
            count &+= 1
        }
    } catch {}
    return count
}

// MARK: - Producers

/// Background threads yielding into every live stream as fast as they can, so the
/// combineLatest child tasks are constantly inside `elementProduced` resuming the
/// consumer's continuation while the storage lock is held.
///
/// They spin without ever blocking, so they run at utility QoS, below every task in the
/// test process. At a higher QoS they took every core they could get: on a 6-core CI VM
/// four of them outranked the default-priority tasks — this test's own medium lanes and
/// the suites Swift Testing runs alongside it — and starved them for seconds, failing
/// timing bounds elsewhere and reading here as a deadlock. Below them, the pump mostly
/// takes spare CPU, which on an idle machine is still plenty. QoS is a preference, not a
/// guarantee — more spinning threads than cores starve everything whatever their QoS —
/// hence also the default thread count scaled to the core count.
private final class Pump: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UInt64: AsyncStream<Int>.Continuation] = [:]
    private var nextID: UInt64 = 0
    private var running = true
    private var paused = false

    func makeStream() -> AsyncStream<Int> {
        let (stream, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(1))
        let id = lock.withLock {
            let id = nextID
            nextID += 1
            continuations[id] = continuation
            return id
        }
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        return stream
    }

    func start(threads: Int) {
        for index in 0..<threads {
            let thread = Thread { [self] in loop(seed: index) }
            thread.qualityOfService = .utility
            thread.start()
        }
    }

    func stop() {
        let remaining = lock.withLock {
            running = false
            let values = Array(continuations.values)
            continuations.removeAll()
            return values
        }
        remaining.forEach { $0.finish() }
    }

    /// Stops yielding without finishing any stream. Finishing resumes a consumer's
    /// continuation, which in a real deadlock would block on the very lock that is stuck.
    func setPaused(_ isPaused: Bool) {
        lock.withLock { paused = isPaused }
    }

    private func remove(_ id: UInt64) {
        lock.withLock { _ = continuations.removeValue(forKey: id) }
    }

    private func loop(seed: Int) {
        var value = seed
        while true {
            let (isRunning, isPaused, snapshot) = lock.withLock { (running, paused, Array(continuations.values)) }
            guard isRunning else { return }
            if isPaused || snapshot.isEmpty {
                usleep(20)
                continue
            }
            for continuation in snapshot {
                continuation.yield(value)
                value &+= 1
            }
        }
    }
}

// MARK: - Watchdog

private final class Monitor: @unchecked Sendable {
    enum Outcome: Sendable {
        case finished
        case deadlocked(String)
    }

    private let lock = NSLock()
    private let laneCount: Int
    private let stallLimit: TimeInterval
    private let recoveryGrace: TimeInterval
    private let pump: Pump
    private let samplePath: String?
    private var lastProgress: [Date]
    private var phases: [String]
    private var finishedLanes = Set<Int>()
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var resolved = false
    private var deadlocked = false
    private var iterations = 0

    init(lanes: Int, stallLimit: TimeInterval, recoveryGrace: TimeInterval, pump: Pump, samplePath: String?) {
        laneCount = lanes
        self.stallLimit = stallLimit
        self.recoveryGrace = recoveryGrace
        self.pump = pump
        self.samplePath = samplePath
        lastProgress = Array(repeating: Date(), count: lanes)
        phases = Array(repeating: "starting", count: lanes)
    }

    var isDeadlocked: Bool { lock.withLock { deadlocked } }
    var iterationCount: Int { lock.withLock { iterations } }

    func onOutcome(_ continuation: CheckedContinuation<Outcome, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func enter(_ lane: Int, phase: String) {
        lock.withLock {
            phases[lane] = phase
            lastProgress[lane] = Date()
        }
    }

    func completedIteration(_ lane: Int) {
        lock.withLock {
            phases[lane] = "between iterations"
            lastProgress[lane] = Date()
            iterations += 1
        }
    }

    func laneFinished(_ lane: Int) {
        let shouldResolve = lock.withLock {
            finishedLanes.insert(lane)
            return finishedLanes.count == laneCount
        }
        if shouldResolve { resolve(.finished) }
    }

    func startWatchdog() {
        let thread = Thread { [self] in watch() }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// A stalled lane is either deadlocked or starved of CPU, and the stall alone cannot
    /// tell them apart: on a 6-core CI VM, lanes that had never been scheduled sat "stuck
    /// in starting" for 4s. So a stall is first a suspicion. The producers — the bulk of
    /// this test's own load — pause, and the lane gets `recoveryGrace` to move again.
    /// Starvation passes; a lock-order inversion holds forever, so the lane stays put.
    private func watch() {
        var suspectedSince: Date?
        while true {
            Thread.sleep(forTimeInterval: 0.25)
            let (done, stuck) = lock.withLock { () -> (Bool, [String]) in
                if resolved { return (true, []) }
                let now = Date()
                let stuck = (0..<laneCount).compactMap { lane -> String? in
                    guard !finishedLanes.contains(lane) else { return nil }
                    let stalled = now.timeIntervalSince(lastProgress[lane])
                    guard stalled > stallLimit else { return nil }
                    return "lane \(lane) stuck \(String(format: "%.1f", stalled))s in \(phases[lane])"
                }
                return (false, stuck)
            }
            if done { return }
            guard !stuck.isEmpty else {
                if suspectedSince != nil {
                    suspectedSince = nil
                    pump.setPaused(false)
                    FileHandle.standardError.write(Data("[#149 stress] stalled lanes moved again: starved, not deadlocked\n".utf8))
                }
                continue
            }
            guard let since = suspectedSince else {
                suspectedSince = Date()
                pump.setPaused(true)
                let description = stuck.joined(separator: "; ")
                FileHandle.standardError.write(Data("[#149 stress] \(description); pausing producers for \(Int(recoveryGrace))s to tell starvation from a deadlock\n".utf8))
                continue
            }
            guard Date().timeIntervalSince(since) >= recoveryGrace else { continue }

            lock.withLock { deadlocked = true }
            let description = stuck.joined(separator: "; ")
            FileHandle.standardError.write(Data("[#149 stress] DEADLOCK REPRODUCED: \(description)\n".utf8))
            if let samplePath { takeSample(to: samplePath) }
            resolve(.deadlocked(description))

            // If the main thread is the one stuck, the test runner can never finish.
            // Give it a moment to report, then take the process down.
            Thread.sleep(forTimeInterval: 10)
            FileHandle.standardError.write(Data("[#149 stress] test runner still alive 10s after the deadlock; exiting\n".utf8))
            exit(1)
        }
    }

    private func resolve(_ outcome: Outcome) {
        let continuation = lock.withLock { () -> CheckedContinuation<Outcome, Never>? in
            guard !resolved else { return nil }
            resolved = true
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: outcome)
    }

    private func takeSample(to path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(getpid())", "2", "-file", path]
        try? process.run()
        process.waitUntilExit()
    }
}
