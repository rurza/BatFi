//
//  HelperShutdown.swift
//
//
//  Carries out what `HelperShutdownPolicy` decides: arms and disarms the process watches,
//  and performs the single shutdown the policy asks for. Everything here is I/O — the rules
//  themselves live in `Shared` precisely so they can be tested without a Mac in a particular
//  state.
//

import Foundation
import os
import Shared

final class HelperShutdown: @unchecked Sendable {
    static let shared = HelperShutdown()

    /// How long the helper may sit spawned with nothing ever connecting to it.
    ///
    /// launchd starts the daemon on a mach service *lookup*, which does not have to become a
    /// connection: the listener's code-signing requirement can reject the client, or the
    /// caller can give up first. Without this the helper stays resident as an idle root
    /// process until reboot. Generous, because the only cost of waiting is that idle
    /// process, while expiring under a client that is merely slow to connect would exit
    /// out from under a real app.
    private static let startupGrace: TimeInterval = 60

    /// Ceiling on the restore that precedes an exit.
    ///
    /// `restoreSystemDefaults()` makes several PowerUI round trips and can spend ~2s
    /// reopening a dropped SMC connection, so it needs real room. It also must not be able
    /// to take unlimited time: this whole design exists to make "the helper always exits"
    /// true, and an unbounded await here would quietly downgrade that to "usually".
    private static let restoreBudget: TimeInterval = 5

    private let logger = Logger(subsystem: Constant.helperBundleIdentifier, category: "HelperShutdown")
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "\(Constant.helperBundleIdentifier).shutdown")

    private var policy = HelperShutdownPolicy()
    private var watches: [pid_t: DispatchSourceProcess] = [:]
    /// Guards against two decisions racing into `exit(0)` — a client process dying while a
    /// `quit()` is already in flight, say. The second one has nothing left to do and must
    /// not run a restore underneath the first.
    private var isExiting = false

    private init() {}

    // MARK: - Entry points

    /// For callers with nowhere to await: the listener's accept and invalidation callbacks,
    /// and the process-watch handlers.
    func handle(_ event: HelperShutdownPolicy.Event) {
        Task { await handle(event, beforeExit: nil) }
    }

    /// - Parameter beforeExit: run after the restore and immediately before `exit(0)`. This
    ///   exists for `quit()`, which has to get its reply onto the connection *after* the
    ///   hardware has been handed back — the caller treats that reply as proof the helper is
    ///   finished, and on the app's own quit path terminates the moment it lands.
    func handle(
        _ event: HelperShutdownPolicy.Event,
        beforeExit: (@Sendable () async -> Void)?
    ) async {
        let decisions = lock.withLock { policy.handle(event) }
        for decision in decisions {
            await apply(decision, beforeExit: beforeExit)
        }
    }

    /// Starts the clock on the startup grace. Called once, as the listener comes up.
    func startGracePeriod() {
        queue.asyncAfter(deadline: .now() + Self.startupGrace) { [weak self] in
            self?.handle(.startupGraceExpired)
        }
    }

    // MARK: - Decisions

    private func apply(
        _ decision: HelperShutdownPolicy.Decision,
        beforeExit: (@Sendable () async -> Void)?
    ) async {
        switch decision {
        case let .watchProcess(pid):
            watchProcess(pid)
        case let .stopWatching(pid):
            stopWatching(pid)
        case let .restoreThenExit(reason):
            await restoreThenExit(reason, beforeExit: beforeExit)
        case let .exitWithoutRestoring(reason):
            guard claimExit() else { return }
            logger.notice("Exiting without restoring: \(String(describing: reason), privacy: .public)")
            await beforeExit?()
            exit(0)
        }
    }

    /// The authoritative signal that a client is gone.
    ///
    /// Unlike an XPC message it needs no cooperation from the app, and unlike connection
    /// invalidation it cannot be produced by anything short of the process actually dying —
    /// which is what makes it safe to release hardware state on.
    private func watchProcess(_ pid: pid_t) {
        // An accepted XPC connection always has a real client pid, so this is a
        // can't-happen. It is checked anyway because of what the two lines below would do
        // with a zero: `kill(0, 0)` addresses the caller's entire process group rather than
        // any one process, and would answer "still alive" no matter what.
        guard pid > 0 else {
            logger.fault("Refusing to watch a client with pid \(pid, privacy: .public)")
            return
        }

        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handle(.clientProcessExited(pid))
        }
        lock.withLock { watches[pid] = source }
        source.resume()

        // `DispatchSource` cannot report a failed kevent registration, and a process that
        // died between the connection being accepted and this line registers nothing at all:
        // the source is created, resumed, and then never fires. Unchecked, that is a root
        // daemon waiting forever for an exit it already missed. The policy discards the
        // duplicate if the real watch fires too.
        if kill(pid, 0) != 0, errno == ESRCH {
            logger.notice("Client \(pid, privacy: .public) was already gone when its watch was armed")
            handle(.clientProcessExited(pid))
        }
    }

    private func stopWatching(_ pid: pid_t) {
        let source = lock.withLock { watches.removeValue(forKey: pid) }
        source?.cancel()
    }

    private func restoreThenExit(
        _ reason: HelperShutdownPolicy.Reason,
        beforeExit: (@Sendable () async -> Void)?
    ) async {
        guard claimExit() else { return }
        logger.notice("Shutting down: \(String(describing: reason), privacy: .public)")
        do {
            try await withTimeout(seconds: Self.restoreBudget) {
                try await SMCService.shared.restoreSystemDefaults()
            }
        } catch {
            // Logged, never fatal. There is nothing left to report this to, and on the
            // existing fleet the firmware band write inside the restore throws because the
            // key is absent — the one case that must not be treated as a failure. Exiting
            // matters more than the restore succeeding: a helper that stays alive here is
            // the defect this file exists to remove.
            logger.error("Restore before exit did not complete: \(error, privacy: .public)")
        }
        await beforeExit?()
        exit(0)
    }

    private func claimExit() -> Bool {
        lock.withLock {
            guard !isExiting else { return false }
            isExiting = true
            return true
        }
    }
}
