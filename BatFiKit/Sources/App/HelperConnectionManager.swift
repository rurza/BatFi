//
//  HelperConnectionManager.swift
//
//
//  Created by Adam Różyński on 06/05/2024.
//

import AppShared
import AsyncAlgorithms
import Clients
import Dependencies
import Foundation
import L10n
import os

protocol HelperConnectionManagerDelegate: AnyObject, Sendable {
    @MainActor
    func showHelperIsNotInstalled()
    @MainActor
    func showHelperIsNotResponding()
    /// The helper is registered, macOS will not start it, and re-registering from here has
    /// already been tried and changed nothing. Separate from `showHelperIsNotResponding()`
    /// because it is the one helper failure with a precise, reliable manual remedy, and the
    /// alert exists to spell that remedy out rather than to report a fault.
    @MainActor
    func showHelperNeedsManualReset()
    /// - Parameter otherCopyIsRunningAt: the other copy's bundle path when it is open right
    ///   now. This is what decides whether the user is asked to quit something or to delete
    ///   it, and it is read at display time rather than when the conflict was found, because
    ///   they may have closed it in between.
    @MainActor
    func showHelperBelongsToAnotherCopy(_ conflict: HelperOwnershipConflict, otherCopyIsRunningAt: String?)
}

final class HelperConnectionManager: @unchecked Sendable {
    @Dependency(\.helperClient) private var helperClient
    @Dependency(\.helperHealthClient) private var helperHealthClient
    @Dependency(\.appChargingState) private var appChargingState
    @Dependency(\.userNotificationsClient) private var userNotificationsClient

    private let logger = Logger(category: "Helper Connection")
    private let state = State()

    /// Owns everything mutable here: the policy itself, the once-per-launch guidance flag,
    /// and the pending probe.
    private actor State {
        private var policy = HelperHealthPolicy()
        private var hasShownGuidance = false
        private var probeTask: Task<Void, Never>?

        func handle(_ event: HelperHealthPolicy.Event) -> [HelperHealthPolicy.Action] {
            policy.handle(event)
        }

        /// Returns whether guidance had already been shown, and marks it shown.
        func claimGuidance() -> Bool {
            defer { hasShownGuidance = true }
            return hasShownGuidance
        }

        func replaceProbe(with task: Task<Void, Never>?) {
            probeTask?.cancel()
            probeTask = task
        }
    }

    weak var delegate: HelperConnectionManagerDelegate?

    /// Set while onboarding is up. Onboarding has its own helper UI, and stacking a modal
    /// on top of it helps nobody.
    var suppressesGuidance = false

    init(delegate: HelperConnectionManagerDelegate) {
        self.delegate = delegate
        observerHelperConnection()
        observeHelperStatus()
        observeConnectionFailures()
    }

    func checkHelperHealth() {
        Task {
            let status = await helperClient.helperStatus()
            await send(.statusObserved(status.helperServiceStatus))
        }
    }

    // MARK: - Inputs

    private func observeHelperStatus() {
        Task {
            for await status in helperClient.observeHelperStatus() {
                await send(.statusObserved(status.helperServiceStatus))
            }
        }
    }

    private func observeConnectionFailures() {
        Task {
            for await _ in helperHealthClient.observeConnectionFailures() {
                // Only meaningful once we believed the helper worked; while degraded the
                // backoff probe already drives the retesting.
                guard await helperHealthClient.currentHealth() == .healthy else { continue }
                await send(.pingFailed)
            }
        }
    }

    // MARK: - Policy loop

    private func send(_ event: HelperHealthPolicy.Event) async {
        for action in await state.handle(event) {
            await perform(action)
        }
    }

    private func perform(_ action: HelperHealthPolicy.Action) async {
        switch action {
        case .verifyWithPing:
            await ping()
        case .verifyIdentity:
            await send(.identityChecked(helperClient.helperOwnership()))
        case let .takeOwnership(conflict):
            await takeOwnership(resolving: conflict)
        case .installHelper:
            do {
                try await helperClient.installHelper()
                await ping()
            } catch {
                await send(.retryFinished(error: error.localizedDescription))
            }
        case .retryRegistrationOnce:
            await retryRegistration()
        case let .publish(health):
            await helperHealthClient.setHealth(health)
        case .showGuidance:
            await showGuidance()
        case let .scheduleProbe(delay):
            await scheduleProbe(after: delay)
        }
    }

    private func ping() async {
        do {
            _ = try await helperClient.pingHelper()
            await send(.pingSucceeded)
        } catch {
            logger.warning("Helper ping failed: \(error.localizedDescription, privacy: .public)")
            await send(.pingFailed)
        }
    }

    /// Delays before each re-registration attempt. `SMAppService` refuses to register over
    /// an existing record, so the unregister has to land first — and Background Task
    /// Management does not finish retiring the old record synchronously. A single fixed
    /// second was observed losing that race and failing with
    /// `SMAppServiceErrorDomain Code=1 "Operation not permitted"`, while the identical
    /// sequence tried again moments later succeeded.
    private static let registrationBackoff: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

    /// The one mutating recovery attempt, and the only thing that actually fixes a record
    /// owned by a different copy of BatFi.
    ///
    /// launchd resolves this daemon through the Background Task Management record's bundle,
    /// not through a path in the plist, so a record registered by another copy of the app —
    /// an older install, a second download, another build — cannot be repaired by the user.
    /// Toggling it in Login Items re-enables the *same* record, still owned by the other
    /// bundle. Only unregistering and registering again from the running app takes ownership.
    ///
    /// Retried rather than attempted once, because the failure mode of giving up here is the
    /// worst one available: the unregister succeeds and the register does not, which leaves
    /// the user with no helper registration at all — strictly worse than the broken record
    /// they started with. Every attempt after the first re-issues the unregister too, since
    /// a register that failed may still have left the old record in place.
    private func retryRegistration() async {
        logger.notice("Helper unreachable; attempting re-registration to take ownership")
        await helperHealthClient.setReclaimingHelper(true)
        let error = await reregister()
        await helperHealthClient.setReclaimingHelper(false)
        await send(.retryFinished(error: error))
    }

    /// Repoints the Background Task Management record at this bundle, and returns a
    /// description of why it could not — nil on success.
    private func reregister() async -> String? {
        var lastError: Error?

        for (attempt, delay) in Self.registrationBackoff.enumerated() {
            do {
                // Tolerated, not fatal: on the later attempts there may be nothing left to
                // remove, and that is a success condition for what follows, not a failure.
                try? await helperClient.removeHelper()
                try await Task.sleep(for: delay)
                try await helperClient.installHelper()
                logger.notice("Helper re-registered on attempt \(attempt + 1, privacy: .public)")
                return nil
            } catch {
                lastError = error
                logger.warning("Helper re-registration attempt \(attempt + 1, privacy: .public) failed: \(error, privacy: .public)")
            }
        }

        // Out of attempts with the record still not ours. Say so with the last error, so the
        // guidance names what went wrong rather than guessing.
        logger.error("Helper re-registration failed after \(Self.registrationBackoff.count, privacy: .public) attempts")
        return lastError?.localizedDescription ?? "Registration did not complete"
    }

    /// Takes the daemon back from another copy of BatFi.
    ///
    /// The order matters more than it looks. The foreign helper is asked to quit *first*,
    /// and not merely to be tidy: it is a root process actively driving the SMC, and one of
    /// the things it may be holding is a firmware charge band, which is enforced by the
    /// hardware and outlives every process that knows about it. Unregistering underneath a
    /// live helper would leave that band armed with nothing left to release it. `quit`
    /// closes the SMC connection and, through `ListenerDelegate`'s invalidation handler,
    /// restores system defaults on the way out.
    ///
    /// `staleBinary` stops there. That case is our own path running a previous build —
    /// after an in-place update — and launchd starts the current binary the next time the
    /// mach service is looked up. Re-registering would cost the user a System Settings
    /// approval to achieve exactly what the process exiting already did.
    private func takeOwnership(resolving conflict: HelperOwnershipConflict) async {
        logger.notice("Taking ownership of the helper from \(conflict.runningExecutablePath, privacy: .public)")

        // Refused rather than attempted when the other copy is open, because a takeover it
        // can undo is not a fix. Both copies would see the other's helper as foreign and
        // trade the record between them; the policy bounds that to one round each, but the
        // user still ends up wherever the last write landed. Naming the other copy is the
        // only thing here that leads to a stable outcome.
        if let other = await OtherRunningCopies.first() {
            logger.error("Another copy of BatFi is running from \(other.path, privacy: .public); not competing for the helper")
            await send(.takeoverFinished(error: "Another copy of BatFi is running from \(other.path)"))
            return
        }

        // Held across the whole sequence, including the quit: from here until a helper of
        // ours answers again there is deliberately nothing on the other end, and everything
        // the app would otherwise send in that window fails. Without this the takeover was
        // observably noisy — a burst of failed charge-limit, inhibit and discharge calls,
        // a MagSafe write, and user-facing notifications for mode changes that were only
        // ever an artefact of the helper being torn down on purpose.
        await helperHealthClient.setReclaimingHelper(true)

        // Best effort throughout: a helper that will not answer a quit is already the
        // unreachable case, and the re-registration below is what fixes that too.
        try? await helperClient.quitHelper()

        // Cleared before the terminal event in every arm, never in a `defer`. The event
        // drives a ping, an identity check and — on success — the re-drive that puts the
        // charge limit back; all of that runs inside `send`, so a flag still set at that
        // point would suppress the very recovery this exists to protect.
        if conflict.kind == .staleBinary {
            logger.notice("Stale helper asked to quit; launchd will start the current build")
            await helperHealthClient.setReclaimingHelper(false)
            await send(.takeoverFinished(error: nil))
            return
        }

        let error = await reregister()
        await helperHealthClient.setReclaimingHelper(false)
        await send(.takeoverFinished(error: error))
    }

    /// Read-only, so it can repeat for as long as the helper stays broken. This is what
    /// lets the app notice a repair it cannot perform itself — the user toggling the
    /// helper in Login Items — without needing a relaunch.
    private func scheduleProbe(after delay: Duration) async {
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.ping()
        }
        await state.replaceProbe(with: task)
    }

    private func showGuidance() async {
        guard !suppressesGuidance else { return }
        guard await !state.claimGuidance() else { return }

        let health = await helperHealthClient.currentHealth()
        await MainActor.run {
            switch health {
            case let .degraded(.foreignHelper(conflict)):
                delegate?.showHelperBelongsToAnotherCopy(conflict, otherCopyIsRunningAt: OtherRunningCopies.first()?.path)
            case .degraded(.staleRegistrationNeedsUserReset):
                delegate?.showHelperNeedsManualReset()
            case .degraded(.registeredButUnreachable), .degraded(.installFailed):
                delegate?.showHelperIsNotResponding()
            default:
                delegate?.showHelperIsNotInstalled()
            }
        }
    }

    // MARK: - Existing: initial-mode watchdog

    func observerHelperConnection() {
        Task {
            for await _ in appChargingState
                .appChargingModeDidChage()
                .debounce(for: .seconds(30))
                .filter({ $0.mode == .initial }) {
                guard await helperHealthClient.currentHealth() == .healthy else { continue }
                // Not `try`: a failed notification used to throw out of the enclosing Task
                // and silently end this watchdog for the rest of the session.
                try? await userNotificationsClient.showUserNotification(
                    title: L10n.Notifications.Notification.Title.cannotReadBatteryInfo,
                    body: L10n.Notifications.Notification.Body.cannotReadBatteryInfo,
                    identifier: "software.micropixels.BatFi.notifications.initial_mode",
                    threadIdentifier: nil,
                    delay: nil
                )
            }
        }
    }
}
