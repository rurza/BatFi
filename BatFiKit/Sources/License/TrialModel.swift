//
//  TrialModel.swift
//  BatFi
//
//  The free trial for this run: read at launch, re-asked when due, started on request, and
//  ended at the moment it ends.
//

import AppShared
import Clients
@preconcurrency import Combine
import Dependencies
import Foundation
import os
import Shared

/// The free trial for this run, beside `LicenseModel`.
///
/// The rules are pure and live in `Shared` (`TrialStatus`); this only reads, asks and keeps
/// time. The server is contacted only to start a trial the person asked for, or to re-ask
/// about a statement this Mac already holds — never with nothing stored, and never while a
/// licence is valid.
@MainActor
public final class TrialModel: ObservableObject {
    @Published
    public private(set) var status: TrialStatus = .notKnown

    /// A start is in flight; a second one is not sent.
    @Published
    public private(set) var isStarting = false

    /// Why the last start failed, for the screen to show. The status is unchanged by it.
    @Published
    public private(set) var startFailure: TrialRequestFailure?

    @Dependency(\.trialClient) private var trialClient
    @Dependency(\.sleepClient) private var sleepClient
    @Dependency(\.date) private var date

    private let logger = Logger(category: "Trial")

    /// Whether the stored statement has been read, or a statement received, in this run.
    /// Until then `status` stays `.notKnown`.
    private var isKnown = false
    private var statement: TrialStatement?
    /// This Mac's fingerprint, nil while its serial cannot be read. The trial is then not known.
    private var fingerprint: String?
    /// Whether a valid licence is held, nil while not known (not read yet, or a stored one
    /// not judged yet); from `licenceValidityChanged(_:)`. The server is not asked about the
    /// trial unless it is false.
    private var licenceIsValid: Bool?
    private var launchRead: Task<Void, Never>?
    /// The re-ask in flight; a second trigger while it runs does not send another.
    private var reconfirming: Task<Void, Never>?
    private var nextJudgement: Task<Void, Never>?
    private var clockChange: AnyCancellable?

    public init() {
        let read = Task { await readStoredStatement() }
        launchRead = read
        Task {
            await read.value
            reconfirmInBackground()
        }
        observeTime()
    }

    /// Returns once the launch read of the stored statement has finished, whatever it found.
    public func launchReadFinished() async {
        await launchRead?.value
    }

    /// The time to judge the held trial at, for days left: the clock, never earlier than the
    /// server's last answer. See `TrialStatement.judgingTime(now:)`.
    public func judgingTime(now: Date) -> Date {
        statement?.judgingTime(now: now) ?? now
    }

    /// The licence model's answer to "is a licence valid", nil while not known. Becoming
    /// known not to be valid — read at launch, or a licence removed — asks the server again
    /// about a held trial when due.
    public func licenceValidityChanged(_ isValid: Bool?) {
        guard isValid != licenceIsValid else { return }
        licenceIsValid = isValid
        if isValid == false {
            reconfirmInBackground()
        }
    }

    /// Asks the server for this Mac's trial. Offered only where no trial is held; a second
    /// call while one is in flight does nothing.
    public func startTrialButtonClicked() {
        guard status == .none, !isStarting else { return }
        isStarting = true
        startFailure = nil
        Task {
            do {
                // Running, or ended when the server reports a trial that already ran out
                // here (after a reinstall): both are answers, not errors.
                accept(try await trialClient.requestTrial())
            } catch {
                startFailure = TrialRequestFailure(error)
            }
            isStarting = false
        }
    }

    public func dismissStartFailureClicked() {
        startFailure = nil
    }

    // MARK: -

    private func readStoredStatement() async {
        let stored: TrialStatement?
        do {
            stored = try await trialClient.storedTrial()
        } catch {
            // Says nothing either way: the trial stays not known, and nothing held is given
            // back for it. Read again on the next wake or clock change.
            logger.error("Could not read the trial from the keychain: \(error.localizedDescription, privacy: .public)")
            return
        }
        // A statement received meanwhile is newer than what was read.
        guard !isKnown else { return }
        statement = stored
        isKnown = true
        judge()
    }

    /// Asks the server again when the re-ask rule says so. In the background: neither launch nor
    /// a wake waits on the network, a failure of any kind leaves the stored statement standing,
    /// and a re-ask already in flight is not joined by a second.
    private func reconfirmInBackground() {
        guard reconfirming == nil else { return }
        reconfirming = Task {
            await reconfirmIfDue()
            reconfirming = nil
        }
    }

    private func reconfirmIfDue() async {
        guard isKnown,
              TrialStatus.asksServerAgain(stored: statement, fingerprint: fingerprint, licenceIsValid: licenceIsValid, now: date.now)
        else { return }
        do {
            accept(try await trialClient.requestTrial())
        } catch {
            logger.notice("Trial re-check failed, keeping the stored statement: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func accept(_ statement: TrialStatement) {
        self.statement = statement
        isKnown = true
        judge()
    }

    /// Judges the held statement by the clock now, and arranges the next judgement.
    private func judge() {
        guard isKnown else { return }
        readFingerprintIfNeeded()
        let next = TrialStatus(statement: statement, fingerprint: fingerprint, now: date.now)
        if next != status {
            logger.notice("Trial: \(String(describing: next), privacy: .public)")
            status = next
        }
        scheduleNextJudgement()
    }

    /// Reads this Mac's fingerprint until it is had. Without it the trial stays not known, and
    /// the next wake or clock change tries again.
    private func readFingerprintIfNeeded() {
        guard fingerprint == nil else { return }
        fingerprint = trialClient.fingerprint()
        if fingerprint == nil {
            logger.error("Could not read this Mac's serial number; the trial is not known")
        }
    }

    private func scheduleNextJudgement() {
        nextJudgement?.cancel()
        nextJudgement = nil
        guard let at = status.nextJudgement else { return }
        // By the clock, not the judging time: the clock is what the timer waits on, and a
        // running trial's end is always ahead of it.
        let delay = max(0, at.timeIntervalSince(date.now))
        nextJudgement = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            self?.judge()
        }
    }

    /// The end is acted on when it happens: a timer does not fire while the Mac sleeps, nor
    /// follow the clock being changed, so both judge again — or, while the stored statement
    /// could not be read, read it again. A clock turned back, or a statement read only now, is
    /// then asked about again when due — that is what undoes a clock turned back at runtime.
    private func observeTime() {
        Task { [weak self, sleepClient] in
            for await _ in sleepClient.macDidWake() {
                await self?.timeMoved()
            }
        }
        clockChange = NotificationCenter.default
            .publisher(for: .NSSystemClockDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.timeMoved() }
            }
    }

    private func timeMoved() async {
        if isKnown {
            judge()
        } else {
            await readStoredStatement()
        }
        reconfirmInBackground()
    }
}
