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
        var lastError: Error?

        for (attempt, delay) in Self.registrationBackoff.enumerated() {
            do {
                // Tolerated, not fatal: on the later attempts there may be nothing left to
                // remove, and that is a success condition for what follows, not a failure.
                try? await helperClient.removeHelper()
                try await Task.sleep(for: delay)
                try await helperClient.installHelper()
                logger.notice("Helper re-registered on attempt \(attempt + 1, privacy: .public)")
                await send(.retryFinished(error: nil))
                return
            } catch {
                lastError = error
                logger.warning("Helper re-registration attempt \(attempt + 1, privacy: .public) failed: \(error, privacy: .public)")
            }
        }

        // Out of attempts with the record still not ours. Say so with the last error, so the
        // guidance names what went wrong rather than guessing.
        logger.error("Helper re-registration failed after \(Self.registrationBackoff.count, privacy: .public) attempts")
        await send(.retryFinished(error: lastError?.localizedDescription ?? "Registration did not complete"))
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
