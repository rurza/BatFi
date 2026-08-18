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
    /// There is no helper, and the alert's button is what adds one.
    ///
    /// - Parameter reason: what `SMAppService` refused with, when it was asked and said no.
    ///   Nil when nothing has been attempted yet — the record is simply absent, which is
    ///   what a user sees after the copy of BatFi that registered it is deleted.
    @MainActor
    func showHelperIsNotInstalled(reason: String?)
    @MainActor
    func showHelperIsNotResponding()
    /// The helper is registered, macOS will not start it, and re-registering from here has
    /// already been tried and changed nothing. Separate from `showHelperIsNotResponding()`
    /// because it is the one helper failure with a precise, reliable manual remedy, and the
    /// alert exists to spell that remedy out rather than to report a fault.
    @MainActor
    func showHelperNeedsManualReset()
    /// The helper is registered and macOS is waiting for the user to allow it. Distinct from
    /// "not installed", which is what this state used to be reported as: the installation
    /// succeeded, there is nothing to repeat, and the only thing missing is a switch that
    /// only the user can turn on.
    @MainActor
    func showHelperNeedsApproval()
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
        /// One automatic modal per launch. Not per state.
        ///
        /// Per-state was tried and was much worse. Helper failures do not arrive one at a
        /// time: a missing record installs into a refusal into a pending approval into a
        /// stale registration, each a genuinely different state, and keying the gate by
        /// state put a modal on screen for every one of them. Dismissing an alert produced
        /// the next alert immediately — three in a row, none of which the user had asked
        /// for.
        ///
        /// The cost is that the first failure of a launch is the one that speaks, even if a
        /// later one would have been more apt. That is the right trade: the status item
        /// carries a warning for as long as anything is wrong, and clicking it reports the
        /// state as it is *now*, on demand, without stacking anything.
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
    ///
    /// Also read by the initial-mode watchdog, which is not a modal but has the same problem:
    /// while this window is up the app has not been set up, so the charging mode it inspects
    /// has not had a chance to leave `.initial` yet.
    var suppressesGuidance = false

    init(delegate: HelperConnectionManagerDelegate) {
        self.delegate = delegate
        observerHelperConnection()
        observeHelperStatus()
        observeConnectionFailures()
    }

    /// Installs on the user's say-so, from the alert that reports the helper missing.
    ///
    /// Routed through the same action the policy emits rather than calling the client
    /// straight, so the attempt lands back in the state machine: a success is followed by
    /// the ping and identity check that decide whether to believe it, and a refusal becomes
    /// `.installFailed` carrying the reason. The user-visible result is macOS's own — the
    /// approval prompt, or the notification about an item added in the background — which is
    /// the point of putting this behind a button rather than a link to System Settings.
    func installHelperRequestedByUser() {
        Task {
            logger.notice("Install requested by the user")
            await perform(.installHelper)
        }
    }

    /// Removes on the user's say-so, from the debug menu.
    ///
    /// The order is load-bearing. Removing the helper drops the XPC connection, and
    /// `observeConnectionFailures()` turns that into a ping failure while the health is still
    /// `.healthy`; the `verifyWithPing` that follows reports a second one, which is the entire
    /// budget `handlePingFailure` needs to re-register. Announcing the removal afterwards would
    /// arrive behind the recovery it exists to prevent, so the policy is told first.
    func removeHelperRequestedByUser() {
        Task {
            logger.notice("Removal requested by the user")
            await send(.removalRequestedByUser)
            try? await helperClient.removeHelper()
        }
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
            // Logged on change only — the stream repeats every 1.5s — and at notice level, so
            // it survives in the persisted log. What the app read from `SMAppService` and when
            // is the first thing any "it said my helper was missing" report needs, and it used
            // to be the one input to this state machine that was never recorded at all.
            var lastLogged: HelperServiceStatus?
            for await status in helperClient.observeHelperStatus() {
                let observed = status.helperServiceStatus
                if observed != lastLogged {
                    lastLogged = observed
                    logger.notice("Helper service status: \(String(describing: observed), privacy: .public)")
                }
                await send(.statusObserved(observed))
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
    /// restores system defaults, closes the SMC connection, and only then answers — see
    /// `XPCServiceHandler.quit()`, which owns that ordering. The restore used to be a side
    /// effect of `ListenerDelegate`'s invalidation handler instead; it is explicit now,
    /// because invalidation no longer implies the client is gone.
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
        // Notice, not debug: this is the app interrupting someone who asked for nothing, and it
        // was the one decision here that left no trace in a log that outlives the session.
        logger.notice("Reporting a helper failure to the user: \(String(describing: health), privacy: .public)")
        await MainActor.run {
            switch health {
            case let .degraded(.foreignHelper(conflict)):
                delegate?.showHelperBelongsToAnotherCopy(conflict, otherCopyIsRunningAt: OtherRunningCopies.first()?.path)
            case .degraded(.staleRegistrationNeedsUserReset):
                delegate?.showHelperNeedsManualReset()
            // Ahead of the default, which is where this used to land. `.requiresApproval`
            // means the registration worked and macOS is holding it pending the user's
            // consent; reporting that as "the helper app is not installed" sends someone
            // back through onboarding to reinstall something that is already installed, and
            // says nothing about the switch that is actually waiting for them.
            case .degraded(.requiresApproval):
                delegate?.showHelperNeedsApproval()
            // Ahead of the not-responding case, and no longer sharing it. That alert says
            // the helper is installed and macOS will not start it; when the registration was
            // refused outright, nothing is installed and there is nothing to toggle.
            case let .degraded(.installFailed(reason)):
                delegate?.showHelperIsNotInstalled(reason: reason)
            case .degraded(.registeredButUnreachable):
                delegate?.showHelperIsNotResponding()
            default:
                delegate?.showHelperIsNotInstalled(reason: nil)
            }
        }
    }

    // MARK: - Existing: initial-mode watchdog

    func observerHelperConnection() {
        Task {
            for await state in appChargingState
                .appChargingModeDidChage()
                .debounce(for: .seconds(30)) {
                // `suppressesGuidance` stands in for "onboarding is up", which is the case the
                // mode filter alone cannot tell apart: onboarding defers `setUpTheApp()` until
                // the helper is in, so `.initial` there is the starting value rather than a
                // reading that never arrived.
                guard await InitialModeWarningPolicy.shouldWarn(
                    mode: state.mode,
                    health: helperHealthClient.currentHealth(),
                    onboardingIsUp: suppressesGuidance
                ) else { continue }
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
